import Foundation
import Security

public enum ObserverRuntimeConfigurationError: Error, Sendable, Equatable {
    case invalidBaseURL
    case invalidProjectID
    case invalidBearerToken
    case credentialMissing
    case keychainFailure(Int32)
}

public struct ObserverRuntimeSettings: Sendable, Equatable {
    public let baseURL: URL
    public let projectID: String

    public init(baseURL: URL, projectID: String) {
        self.baseURL = baseURL
        self.projectID = projectID
    }
}

public struct ObserverRuntimeConfigurationStore {
    public static let defaultBaseURLString = "https://vcw-observer.tail40ed70.ts.net:8443"
    public static let defaultProjectID = "vcw-acceptance"

    private static let baseURLKey = "observer.runtime.base-url"
    private static let projectIDKey = "observer.runtime.project-id"
    private static let keychainAccount = "observer-read-bearer"

    private let defaults: UserDefaults
    private let keychainService: String

    public init(
        defaults: UserDefaults = .standard,
        keychainService: String = "com.fnauy.observer.transport"
    ) {
        self.defaults = defaults
        self.keychainService = keychainService
    }

    public static func validatedSettings(
        baseURLString: String,
        projectID: String
    ) throws -> ObserverRuntimeSettings {
        let rawURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawProject = projectID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard var components = URLComponents(string: rawURL),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw ObserverRuntimeConfigurationError.invalidBaseURL
        }
        components.path = ""
        guard let url = components.url else {
            throw ObserverRuntimeConfigurationError.invalidBaseURL
        }

        guard rawProject.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#,
            options: .regularExpression
        ) != nil else {
            throw ObserverRuntimeConfigurationError.invalidProjectID
        }

        return ObserverRuntimeSettings(baseURL: url, projectID: rawProject)
    }

    public static func validatedBearerToken(_ token: String) throws -> String {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.count <= 256,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw ObserverRuntimeConfigurationError.invalidBearerToken
        }
        return value
    }

    public func loadSettings() -> ObserverRuntimeSettings {
        let base = defaults.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURLString
        let project = defaults.string(forKey: Self.projectIDKey) ?? Self.defaultProjectID
        if let settings = try? Self.validatedSettings(
            baseURLString: base,
            projectID: project
        ) {
            return settings
        }

        return ObserverRuntimeSettings(
            baseURL: URL(string: Self.defaultBaseURLString)!,
            projectID: Self.defaultProjectID
        )
    }

    @discardableResult
    public func saveSettings(
        baseURLString: String,
        projectID: String
    ) throws -> ObserverRuntimeSettings {
        let settings = try Self.validatedSettings(
            baseURLString: baseURLString,
            projectID: projectID
        )
        defaults.set(settings.baseURL.absoluteString, forKey: Self.baseURLKey)
        defaults.set(settings.projectID, forKey: Self.projectIDKey)
        return settings
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

    public func makeTransportConfiguration() throws -> ObserverTransportConfiguration? {
        guard let token = try loadBearerToken() else {
            return nil
        }
        let settings = loadSettings()
        return try ObserverTransportConfiguration(
            baseURL: settings.baseURL,
            bearerToken: token,
            projectID: settings.projectID
        )
    }
}
