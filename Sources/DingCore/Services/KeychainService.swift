import Foundation
import Security

public enum KeychainService {
    private static let service = "dev.sijun.ding"

    public static func saveDeviceToken(_ token: String) throws {
        try save(token, account: "device-token")
    }

    public static func getDeviceToken() throws -> String {
        try get(account: "device-token")
    }

    public static func saveAPIKey(_ key: String) throws {
        try save(key, account: "api-key")
    }

    public static func getAPIKey() throws -> String {
        try get(account: "api-key")
    }

    public static func deleteAll() {
        delete(account: "device-token")
        delete(account: "api-key")
    }

    private static func save(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw DingError.configurationError("Failed to encode value")
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DingError.configurationError("Keychain save failed: \(status)")
        }
    }

    private static func get(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw DingError.configurationError("Keychain item not found: \(account)")
        }
        return value
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
