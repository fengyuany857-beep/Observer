import Foundation
import Security

public struct ObserverOwnerCredentialStore {
    private static let keychainAccount = "observer-owner-bearer"

    private let keychainService: String

    public init(
        keychainService: String = "com.fnauy.observer.transport"
    ) {
        self.keychainService = keychainService
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
            kSecAttrAccount as String: Self.keychainAccount,
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
            kSecAttrAccount as String: Self.keychainAccount
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
            kSecAttrAccount as String: Self.keychainAccount
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
