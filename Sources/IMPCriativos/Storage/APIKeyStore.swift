import Foundation
import Security

/// Guarda as chaves de API num arquivo só deste usuário do Mac:
/// ~/Library/Application Support/IMP Criativos/chaves.json (permissão 600 — só a sua conta lê).
///
/// Até a 1.0.0-beta.9 as chaves ficavam no Keychain. Como o app é assinado sem conta de
/// desenvolvedor Apple, cada versão nova tem outra identidade, e o macOS pedia a senha das
/// chaves de novo (às vezes sem parar). Agora nada passa pelo Keychain no uso normal.
/// Na primeira abertura, o app tenta copiar as chaves antigas do Keychain **sem mostrar
/// nenhum pedido**; se o macOS não deixar, basta colar as chaves de novo em Configurações.
enum APIKeyStore {
    private static let lock = NSLock()
    private static var cache: [String: String]?

    private static var fileURL: URL { Paths.appSupport.appendingPathComponent("chaves.json") }
    private static let migrationFlag = "apiKeys.keychainMigrationDone"

    // MARK: - API pública

    static func save(_ value: String, for provider: ProviderKind) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock(); defer { lock.unlock() }
        var keys = loadAllLocked()
        if trimmed.isEmpty { keys.removeValue(forKey: provider.rawValue) } else { keys[provider.rawValue] = trimmed }
        try writeLocked(keys)
    }

    static func load(_ provider: ProviderKind) -> String? {
        lock.lock(); defer { lock.unlock() }
        let s = loadAllLocked()[provider.rawValue]
        return (s?.isEmpty ?? true) ? nil : s
    }

    static func delete(_ provider: ProviderKind) {
        lock.lock(); defer { lock.unlock() }
        var keys = loadAllLocked()
        guard keys.removeValue(forKey: provider.rawValue) != nil else { return }
        try? writeLocked(keys)
    }

    static func hasKey(_ provider: ProviderKind) -> Bool { load(provider) != nil }

    // MARK: - Arquivo

    /// Lê do cache; na primeira vez lê o arquivo (e migra do Keychain, se for o caso).
    private static func loadAllLocked() -> [String: String] {
        if let cache { return cache }
        var keys: [String: String] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            keys = decoded
            ensurePrivatePermissions()
        }
        if !UserDefaults.standard.bool(forKey: migrationFlag) {
            UserDefaults.standard.set(true, forKey: migrationFlag)
            let migrated = migrateFromKeychainSilently(into: &keys)
            if migrated > 0 { try? writeLocked(keys) }
        }
        cache = keys
        return keys
    }

    private static func writeLocked(_ keys: [String: String]) throws {
        do {
            let data = try JSONEncoder().encode(keys)
            try data.write(to: fileURL, options: [.atomic])
            ensurePrivatePermissions()
            cache = keys
        } catch {
            throw NSError(domain: "APIKeyStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Não foi possível salvar a chave (\(error.localizedDescription))."])
        }
    }

    private static func ensurePrivatePermissions() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    // MARK: - Migração do Keychain (versões até a beta.9), sem nenhum pedido de senha

    private static let legacyService = "com.imperaservices.impcriativos"

    private static func migrateFromKeychainSilently(into keys: inout [String: String]) -> Int {
        // Impede o macOS de mostrar qualquer janela de senha durante esta leitura.
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(true) }

        var count = 0
        for provider in ProviderKind.allCases where keys[provider.rawValue] == nil {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyService,
                kSecAttrAccount as String: "api-key-\(provider.rawValue)",
            ]
            var query = base
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { continue }
            let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }
            keys[provider.rawValue] = s
            count += 1
            // Remove a cópia antiga do Keychain (também sem pedido; se não der, fica lá e não atrapalha).
            SecItemDelete(base as CFDictionary)
        }
        return count
    }
}
