import Foundation
import Security

enum KeyStore {
    private static let service = "local.conversation.translator.deepseek"
    private static let account = "api-key"
    private static func query(_ provider: APIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: provider == .deepseek ? service : "local.conversation.translator.\(provider.rawValue)", kSecAttrAccount as String: account]
    }
    static func read(provider: APIProvider = .deepseek) -> String {
        var q = query(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String, provider: APIProvider = .deepseek) throws {
        if value.isEmpty {
            let status = SecItemDelete(query(provider) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw TranslatorError.message("无法删除密钥（\(status)）")
            }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(provider) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw TranslatorError.message("无法保存密钥（\(status)）") }
        var q = query(provider)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(q as CFDictionary, nil)
        guard added == errSecSuccess else { throw TranslatorError.message("无法保存密钥（\(added)）") }
    }
}
