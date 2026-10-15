import Foundation
import Security

/// Keychain coordinates for secrets. The Discord bot token and the OpenAI API key live only here, never in store.json.
enum Secrets {
    static let discordService = "com.tofu.discord"
    static let discordAccount = "bot-token"
    static let openAIService = "com.tofu.openai"
    static let openAIAccount = "api-key"
    static let googleService = "com.tofu.google"
    static let googleAccount = "refresh-token"
}

/// Minimal generic-password wrapper around the login keychain.
enum Keychain {
    /// The stored UTF-8 string, or nil when missing or unreadable.
    static func get(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Creates or overwrites the item. Returns false if the keychain rejected the write.
    @discardableResult static func set(_ value: String, service: String, account: String) -> Bool {
        let query = baseQuery(service: service, account: account)
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrLabel as String] = service
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the item if present. Missing items are not an error.
    static func delete(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
