import Foundation
import XCTest
@testable import ObserverReadAPI

final class ObserverReadAPITests: XCTestCase {
    func testConfigurationRejectsNonHTTPS() {
        XCTAssertThrowsError(
            try ObserverReadAPIConfiguration(
                baseURL: URL(string: "http://observer.test")!,
                bearerToken: "token"
            )
        ) { error in
            XCTAssertEqual(
                error as? ObserverReadAPIError,
                .invalidConfiguration("HTTPS_REQUIRED")
            )
        }
    }

    func testConfigurationRejectsWhitespaceToken() {
        XCTAssertThrowsError(
            try ObserverReadAPIConfiguration(
                baseURL: URL(string: "https://observer.test")!,
                bearerToken: "bad token"
            )
        ) { error in
            XCTAssertEqual(
                error as? ObserverReadAPIError,
                .invalidConfiguration("TOKEN_INVALID")
            )
        }
    }

    func testJobStateClassPreservesUnknownFutureStates() {
        XCTAssertEqual(
            ObserverJobStateClass(rawValue: "LAST_OBSERVED_ACTIVE"),
            .lastObservedActive
        )
        XCTAssertEqual(
            ObserverJobStateClass(rawValue: "TERMINAL_CONFIRMED"),
            .terminalConfirmed
        )
        XCTAssertNil(ObserverJobStateClass(rawValue: "FUTURE_STATE"))
    }

    func testEventSessionLinkRequiresExactSessionID() {
        let linked = ObserverReadEvent(
            eventID: 1,
            eventIdentity: "evt-1",
            eventType: "TOOL_EVENT",
            createdAt: Date(timeIntervalSince1970: 1),
            sessionID: "session-a",
            projectID: "project-a",
            source: "gateway",
            authoritative: false,
            payloadSummary: "{}"
        )
        let projectOnly = ObserverReadEvent(
            eventID: 2,
            eventIdentity: "evt-2",
            eventType: "PROJECT_EVENT",
            createdAt: Date(timeIntervalSince1970: 2),
            sessionID: nil,
            projectID: "project-a",
            source: "gateway",
            authoritative: true,
            payloadSummary: "{}"
        )
        let otherSession = ObserverReadEvent(
            eventID: 3,
            eventIdentity: "evt-3",
            eventType: "TOOL_EVENT",
            createdAt: Date(timeIntervalSince1970: 3),
            sessionID: "session-b",
            projectID: "project-a",
            source: "gateway",
            authoritative: true,
            payloadSummary: "{}"
        )
        let page = ObserverReadEventsPage(
            sourceInstanceID: "source-1",
            projectID: "project-a",
            eventCursor: 3,
            events: [linked, projectOnly, otherSession]
        )

        XCTAssertEqual(page.eventsForSession("session-a").map(\.eventID), [1])
    }

    func testEventsRejectNegativeCursorBeforeNetwork() async throws {
        let configuration = try ObserverReadAPIConfiguration(
            baseURL: URL(string: "https://observer.invalid")!,
            bearerToken: "token"
        )
        let client = ObserverReadAPIClient(configuration: configuration)
        do {
            _ = try await client.events(projectID: "project-a", afterID: -1)
            XCTFail("negative cursor must be rejected")
        } catch let error as ObserverReadAPIError {
            XCTAssertEqual(error, .invalidCursor)
        }
    }

    func testEffectsRejectOversizedLimitBeforeNetwork() async throws {
        let configuration = try ObserverReadAPIConfiguration(
            baseURL: URL(string: "https://observer.invalid")!,
            bearerToken: "token"
        )
        let client = ObserverReadAPIClient(configuration: configuration)
        do {
            _ = try await client.effects(projectID: "project-a", limit: 101)
            XCTFail("oversized effect page must be rejected")
        } catch let error as ObserverReadAPIError {
            XCTAssertEqual(error, .invalidLimit)
        }
    }
}
