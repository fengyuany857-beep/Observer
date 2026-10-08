import Foundation
import Security

public enum ObserverOwnerCredentialPurpose: String, Sendable {
    case approvals = "observer-owner-bearer"
    case sessionClose = "observer-owner-close-bearer"
}

public struct ObserverOwnerCredentialStore {
    public let purpose: ObserverOwnerCredentialPurpose
    private let keychainService: String

    public init(
        keychainService: String = "com.fnauy.observer.transport",
        purpose: ObserverOwnerCredentialPurpose = .approvals
    ) {
        self.keychainService = keychainService
        self.purpose = purpose
    }

    public static func validatedBearerToken(_ token: String) throws -> String {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix(ObserverOwnerContract.tokenPrefix),
              !value.isEmpty,
              value.count <= 249,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw ObserverOwnerControlError.invalidConfiguration("OWNER_TOKEN_INVALID")
        }
        return value
    }

    public func loadBearerToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: purpose.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw ObserverRuntimeConfigurationError.keychainFailure(status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw ObserverRuntimeConfigurationError.keychainFailure(errSecDecode)
        }
        return try Self.validatedBearerToken(value)
    }

    public func saveBearerToken(_ token: String) throws {
        let value = try Self.validatedBearerToken(token)
        let data = Data(value.utf8)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: purpose.rawValue
        ]

        var status = SecItemUpdate(
            identity as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var add = identity
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw ObserverRuntimeConfigurationError.keychainFailure(status)
        }
    }

    public func deleteBearerToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: purpose.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ObserverRuntimeConfigurationError.keychainFailure(status)
        }
    }

    public func makeConfiguration(
        settings: ObserverRuntimeSettings,
        requestTimeout: TimeInterval = 8
    ) throws -> ObserverOwnerControlConfiguration? {
        guard let token = try loadBearerToken() else { return nil }
        return try ObserverOwnerControlConfiguration(
            baseURL: settings.baseURL,
            bearerToken: token,
            projectID: settings.projectID,
            requestTimeout: requestTimeout
        )
    }
}

/// Durable Close idempotency identity, deliberately isolated from all bearer accounts.
/// Records are not cleared on success: an old Session must never be closed twice.
public struct ObserverSessionCloseAttemptStore {
    public static let accountPrefix = "observer-close-attempt-v1:"
    private let keychainService: String

    public init(keychainService: String = "com.fnauy.observer.transport") {
        self.keychainService = keychainService
    }

    public static func account(baseURL: URL, projectID: String, sessionID: String) -> String {
        let scope = [baseURL.absoluteString, projectID, sessionID]
            .map { "\($0.utf8.count):\($0)" }.joined()
        return accountPrefix + Data(scope.utf8).base64EncodedString()
    }

    public static func isValidAttemptID(_ value: String) -> Bool {
        value.range(
            of: #"^close:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
            options: .regularExpression
        ) != nil
    }

    private func identity(baseURL: URL, projectID: String, sessionID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: Self.account(
                baseURL: baseURL, projectID: projectID, sessionID: sessionID
            )
        ]
    }

    public func load(baseURL: URL, projectID: String, sessionID: String) throws -> String? {
        var query = identity(baseURL: baseURL, projectID: projectID, sessionID: sessionID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw ObserverRuntimeConfigurationError.keychainFailure(status)
        }
        guard let data = item as? Data,
              let attemptID = String(data: data, encoding: .utf8),
              Self.isValidAttemptID(attemptID) else {
            throw ObserverOwnerControlError.invalidConfiguration("CLOSE_ATTEMPT_CORRUPT")
        }
        return attemptID
    }

    public func record(
        _ attemptID: String, baseURL: URL, projectID: String, sessionID: String
    ) throws {
        guard Self.isValidAttemptID(attemptID) else {
            throw ObserverOwnerControlError.invalidConfiguration("CLOSE_ATTEMPT_ID_INVALID")
        }
        var add = identity(baseURL: baseURL, projectID: projectID, sessionID: sessionID)
        add[kSecValueData as String] = Data(attemptID.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard try load(baseURL: baseURL, projectID: projectID, sessionID: sessionID) == attemptID else {
                throw ObserverOwnerControlError.invalidConfiguration("CLOSE_ATTEMPT_ALREADY_EXISTS")
            }
            return
        }
        guard status == errSecSuccess else {
            throw ObserverRuntimeConfigurationError.keychainFailure(status)
        }
    }
}
