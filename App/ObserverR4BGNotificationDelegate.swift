import Foundation
import UIKit
import UserNotifications

/// Isolated integration candidate. NOT wired to @UIApplicationDelegateAdaptor until signed APNs Gate passes.
/// Never accesses SwiftUI ViewModels, session-close credentials or project runtime claims.
@MainActor
final class ObserverR4BGNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = ObserverR4BGNotificationDelegate()
    static let category = "OBSERVER_VCW_APPROVAL_V1"
    static let allowAction = "OBSERVER_APPROVAL_ALLOW"
    static let denyAction = "OBSERVER_APPROVAL_DENY"

    static func registerCategories() {
        let allow = UNNotificationAction(identifier: allowAction, title: "Allow", options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: denyAction, title: "Deny", options: [])
        let category = UNNotificationCategory(identifier: category, actions: [deny, allow], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.content.categoryIdentifier == Self.category,
              let decision = Self.decision(from: response.actionIdentifier),
              let approvalID = response.notification.request.content.userInfo["approval_id"] as? String,
              let projectID = response.notification.request.content.userInfo["project_id"] as? String else {
            completionHandler()
            return
        }
        // Apple provides a bounded execution opportunity after user interaction; not permanent background runtime.
        // This callback must be completed even if authority/recovery is unavailable.
        let end = ObserverR4BGCompletionFence(completion: completionHandler)
        let backgroundID = UIApplication.shared.beginBackgroundTask(withName: "Observer Approval Action") {
            end.complete()
        }
        end.backgroundTaskID = backgroundID

        Task { @MainActor in
            defer { end.complete() }
            let settings = ObserverRuntimeConfigurationStore().loadSettings()
            guard projectID == settings.projectID else { return }
            let credentialStore = ObserverOwnerCredentialStore(purpose: .approvals)
            guard let configuration = try? credentialStore.makeConfiguration(settings: settings) else { return }
            guard let journalURL = try? ObserverApprovalAttemptJournal.defaultURL() else { return }
            let service = ObserverBGOwnerAdapter(owner: ObserverOwnerControlClient(configuration: configuration))
            let engine = ObserverBGApprovalActionEngine(
                journal: ObserverApprovalAttemptJournal(databaseURL: journalURL),
                service: service,
                scope: ObserverApprovalAttemptJournal.scope(baseURL: configuration.baseURL, projectID: projectID),
                configuredProjectID: projectID
            )
            let outcome = await engine.handle(
                approvalID: approvalID,
                payloadProjectID: projectID,
                decision: decision,
                now: Date().timeIntervalSince1970
            )
            // No notification action ever claims a Session. No optimistic "Approved" UI.
            _ = outcome
        }
    }

    private static func decision(from identifier: String) -> String? {
        if identifier == allowAction { return "ALLOW" }
        if identifier == denyAction { return "DENY" }
        return nil
    }
}

/// Exactly-once completion guard for a system-owned notification callback.
/// All mutations are confined to the main actor; expiration and normal task completion race safely.
@MainActor
private final class ObserverR4BGCompletionFence {
    private var completed = false
    private let completion: () -> Void
    var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    init(completion: @escaping () -> Void) { self.completion = completion }

    func complete() {
        guard !completed else { return }
        completed = true
        completion()
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
}
