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
}
