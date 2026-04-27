import Foundation
import Security

enum KeychainStore {
    private static let service = "com.jz.JZLLMContext"

    static func keychainRef(for provider: ProviderType) -> String {
        "jzllmcontext.\(provider.rawValue).apikey"
    }

    static func save(apiKey: String, for provider: ProviderType) throws {
        let account = keychainRef(for: provider)
        let data = Data(apiKey.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(for provider: ProviderType) throws -> String {
        let account = keychainRef(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.notFound
        }
        return key
    }

    static func hasKey(for provider: ProviderType) -> Bool {
        (try? load(for: provider)) != nil
    }

    static func delete(for provider: ProviderType) {
        let account = keychainRef(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case notFound

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status): "Keychain save failed: \(status)"
        case .notFound: "API klíč nenalezen v Keychain"
        }
    }
}
