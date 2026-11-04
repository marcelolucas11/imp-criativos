import Foundation
import Security

/// Guarda as chaves de API no Keychain do macOS (criptografadas, nunca em arquivo).
enum KeychainStore {
    private static let service = "com.imperaservices.impcriativos"

    static func account(for provider: ProviderKind) -> String { "api-key-\(provider.rawValue)" }

    static func save(_ value: String, for provider: ProviderKind) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        delete(provider)
        guard !trimmed.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
            kSecAttrLabel as String: "IMP Criativos — chave \(provider.label)",
            kSecValueData as String: Data(trimmed.utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Não foi possível salvar no Keychain (código \(status))."])
        }
    }

    static func load(_ provider: ProviderKind) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        let s = String(decoding: data, as: UTF8.self)
        return s.isEmpty ? nil : s
    }

    static func delete(_ provider: ProviderKind) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func hasKey(_ provider: ProviderKind) -> Bool { load(provider) != nil }
}
