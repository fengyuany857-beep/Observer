import Foundation

@main
struct ObserverRuntimeConfigurationTests {
    private static var checks = 0
    private static var failures = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !condition() {
            failures += 1
            print("FAIL \(name)")
        }
    }

    private static func rejects(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            expect(false, name)
        } catch {
            expect(true, name)
        }
    }

    static func main() {
        do {
            let defaults = try ObserverRuntimeConfigurationStore.validatedSettings(
                baseURLString: ObserverRuntimeConfigurationStore.defaultBaseURLString,
                projectID: ObserverRuntimeConfigurationStore.defaultProjectID
            )
            expect(defaults.baseURL.scheme == "https", "default URL requires HTTPS")
            expect(defaults.baseURL.host == "vcw-observer-read-edge.vercel.app", "default stable edge host")
            expect(defaults.baseURL.port == nil, "default stable edge uses standard HTTPS port")
            expect(defaults.projectID == "vcw-acceptance", "default project scope")
        } catch {
            expect(false, "defaults validate")
        }

        rejects("HTTP URL rejected") {
            _ = try ObserverRuntimeConfigurationStore.validatedSettings(
                baseURLString: "http://example.test:8443",
                projectID: "vcw-acceptance"
            )
        }

        rejects("URL query rejected") {
            _ = try ObserverRuntimeConfigurationStore.validatedSettings(
                baseURLString: "https://example.test:8443?token=bad",
                projectID: "vcw-acceptance"
            )
        }

        rejects("URL credentials rejected") {
            _ = try ObserverRuntimeConfigurationStore.validatedSettings(
                baseURLString: "https://user:pass@example.test:8443",
                projectID: "vcw-acceptance"
            )
        }

        rejects("invalid project rejected") {
            _ = try ObserverRuntimeConfigurationStore.validatedSettings(
                baseURLString: "https://example.test:8443",
                projectID: "../other"
            )
        }

        do {
            let token = try ObserverRuntimeConfigurationStore.validatedBearerToken("obsr_example")
            expect(token == "obsr_example", "token accepted without mutation")
        } catch {
            expect(false, "valid token accepted")
        }

        rejects("token whitespace rejected") {
            _ = try ObserverRuntimeConfigurationStore.validatedBearerToken("obsr_bad token")
        }

        rejects("owner token rejected by read client") {
            _ = try ObserverRuntimeConfigurationStore.validatedBearerToken("obsw_owner_token")
        }

        do {
            let token = try ObserverOwnerCredentialStore.validatedBearerToken("obsw_owner_token")
            expect(token == "obsw_owner_token", "owner token accepted by owner store")
        } catch {
            expect(false, "valid owner token accepted")
        }

        let approvalsStore = ObserverOwnerCredentialStore()
        let closeStore = ObserverOwnerCredentialStore(purpose: .sessionClose)
        expect(approvalsStore.purpose == .approvals, "existing owner defaults to approval Keychain identity")
        expect(closeStore.purpose == .sessionClose, "close uses separate Keychain identity")
        expect(approvalsStore.purpose.rawValue == "observer-owner-bearer",
               "legacy approval Keychain account preserved")
        expect(closeStore.purpose.rawValue == "observer-owner-close-bearer",
               "Close Keychain account separate from approval")
        expect(closeStore.purpose != approvalsStore.purpose,
               "Close and Approval cannot address same Keychain account")

        let exampleAttempt = "close:12345678-1234-4abc-9abc-123456789abc"
        expect(ObserverSessionCloseAttemptStore.isValidAttemptID(exampleAttempt),
               "Close journal accepts a well-formed request identity")
        expect(!ObserverSessionCloseAttemptStore.isValidAttemptID("close:bad"),
               "Close journal rejects malformed request identity")
        expect(!ObserverSessionCloseAttemptStore.isValidAttemptID("obsw_secret"),
               "Close journal cannot store owner credentials")
        let closeURL = URL(string: "https://example.test")!
        let account = ObserverSessionCloseAttemptStore.account(
            baseURL: closeURL, projectID: "vcw-acceptance", sessionID: "s_one"
        )
        expect(account.hasPrefix(ObserverSessionCloseAttemptStore.accountPrefix),
               "Close journal Keychain account has a separate namespace")
        expect(account == ObserverSessionCloseAttemptStore.account(
            baseURL: closeURL, projectID: "vcw-acceptance", sessionID: "s_one"
        ), "Close journal account is stable across app launches")
        expect(account != ObserverSessionCloseAttemptStore.account(
            baseURL: closeURL, projectID: "vcw-acceptance", sessionID: "s_two"
        ), "different session cannot reuse another Close identity")
        expect(account != ObserverSessionCloseAttemptStore.account(
            baseURL: closeURL, projectID: "different-project", sessionID: "s_one"
        ), "different project cannot reuse another Close identity")
        expect(account != ObserverSessionCloseAttemptStore.account(
            baseURL: URL(string: "https://other.example.test")!,
            projectID: "vcw-acceptance", sessionID: "s_one"
        ), "different host cannot reuse another Close identity")
        expect(account != approvalsStore.purpose.rawValue
               && account != closeStore.purpose.rawValue,
               "Close journal does not overwrite either owner credential")

        // Integration with the real Security Keychain; use a disposable isolated service.
        let disposableService = "com.fnauy.observer.ci.close-attempt." + UUID().uuidString
        let journal = ObserverSessionCloseAttemptStore(keychainService: disposableService)
        let reloaded = ObserverSessionCloseAttemptStore(keychainService: disposableService)
        do {
            try journal.record(
                exampleAttempt, baseURL: closeURL,
                projectID: "vcw-acceptance", sessionID: "s_one"
            )
            let stored = try reloaded.load(
                baseURL: closeURL, projectID: "vcw-acceptance", sessionID: "s_one"
            )
            expect(stored == exampleAttempt, "Close attempt survives a new store instance")
            try journal.record(
                exampleAttempt, baseURL: closeURL,
                projectID: "vcw-acceptance", sessionID: "s_one"
            )
            expect(true, "same Close attempt is idempotently recordable")
        } catch {
            expect(false, "Keychain journal write/reload succeeds")
        }
        rejects("second different Close attempt cannot replace persisted identity") {
            try journal.record(
                "close:abcdef12-1234-4abc-9abc-123456789abc",
                baseURL: closeURL, projectID: "vcw-acceptance", sessionID: "s_one"
            )
        }
        do {
            let other = try reloaded.load(
                baseURL: closeURL, projectID: "other-project", sessionID: "s_one"
            )
            expect(other == nil, "journal never crosses project authority scope")
        } catch {
            expect(false, "journal scope isolation reads without failure")
        }

        rejects("read token rejected by owner store") {
            _ = try ObserverOwnerCredentialStore.validatedBearerToken("obsr_read_token")
        }

        rejects("oversized token rejected") {
            _ = try ObserverRuntimeConfigurationStore.validatedBearerToken(
                String(repeating: "x", count: 257)
            )
        }

        print(
            "Observer runtime configuration tests: checks=\(checks) " +
            "pass=\(checks - failures) fail=\(failures)"
        )
        if failures > 0 {
            exit(1)
        }
    }
}
