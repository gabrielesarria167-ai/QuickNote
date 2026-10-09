import Foundation
import Security

/// Where the Gemini API key is kept.
@MainActor
protocol KeyStore {
    /// Whether a key is stored. Never reads the key itself, so it can't ask the user for anything.
    func hasKey() -> Bool
    func read() throws -> String?
    /// Stores the key without the whitespace around it. Throws `KeyStoreError.empty` for a blank one.
    func save(_ key: String) throws
    func delete() throws
}

enum KeyStoreError: LocalizedError, Equatable {
    case empty
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .empty:
            "Paste an API key first."
        case .keychain(let status):
            "The Keychain said: \(SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)")"
        }
    }

    /// The key without the whitespace and line breaks that come along when it is pasted.
    static func cleaned(_ key: String) throws -> String {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw KeyStoreError.empty }
        return key
    }
}

/// The key as a generic password in the login Keychain, under this app's bundle id. It uses the
/// legacy file-based keychain (no `kSecUseDataProtectionKeychain`), which needs no entitlement. The
/// key is remembered in memory once read or saved, so the Keychain is asked only once per launch.
@MainActor
final class KeychainKeyStore: KeyStore {
    private let service = Bundle.main.bundleIdentifier ?? "com.gabrielesarria.quicknote"
    private let account = "gemini-api-key"
    private var cached: String?

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func hasKey() -> Bool {
        if cached != nil { return true }
        var request = query
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(request as CFDictionary, nil)
        // A locked keychain refuses to answer without asking, which means there is something in it.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    func read() throws -> String? {
        if let cached { return cached }
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeyStoreError.keychain(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else { return nil }
        cached = key
        return key
    }

    func save(_ key: String) throws {
        let key = try KeyStoreError.cleaned(key)
        let data = Data(key.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Gemini API key"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeyStoreError.keychain(status) }
        cached = key
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyStoreError.keychain(status) }
        cached = nil
    }
}

/// A key store that keeps the key in memory, for tests and previews.
@MainActor
final class InMemoryKeyStore: KeyStore {
    private var key: String?

    init(key: String? = nil) {
        self.key = key
    }

    func hasKey() -> Bool { key != nil }

    func read() throws -> String? { key }

    func save(_ key: String) throws {
        self.key = try KeyStoreError.cleaned(key)
    }

    func delete() throws {
        key = nil
    }
}
