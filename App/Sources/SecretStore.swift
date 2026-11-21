import Foundation
import Security

/**
 Small credentials that should not sit in UserDefaults (which is plain text in device backups).

 A sideloaded build can be re-signed in ways that make the Keychain unavailable, so the store never
 becomes the only copy by accident: callers keep their old value until a write has really succeeded.
 Public client identifiers (a Mapbox `pk.` token, the map style URLs) are not secrets, but a token
 that bills an account is still better kept out of backups and screenshots of defaults.
 */
enum SecretStore {
    private static func query(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(service: String, account: String) -> String? {
        var request = query(service, account)
        request[kSecReturnData as String] = true
        var data: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &data) == errSecSuccess,
              let data = data as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// An empty value deletes the item. Returns whether the Keychain now holds exactly [value].
    @discardableResult
    static func write(_ value: String, service: String, account: String) -> Bool {
        if value.isEmpty {
            let status = SecItemDelete(query(service, account) as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(service, account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var request = query(service, account)
        request[kSecValueData as String] = data
        // Needed in the background (navigation), never copied to another device.
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(request as CFDictionary, nil) == errSecSuccess
    }
}

/// The user's Mapbox public token, migrated out of UserDefaults without ever losing it.
enum MapboxCredential {
    private static let service = "Kite.Mapbox"
    private static let account = "access-token"
    private static let legacyKey = "mapboxToken"

    /// The stored token. A token found only in UserDefaults moves to the Keychain; the old copy is
    /// removed only after the Keychain confirms it holds the same value.
    static func load(defaults: UserDefaults = .standard) -> String {
        if let stored = SecretStore.read(service: service, account: account), !stored.isEmpty {
            defaults.removeObject(forKey: legacyKey)
            return stored
        }
        let legacy = defaults.string(forKey: legacyKey) ?? ""
        if !legacy.isEmpty, SecretStore.write(legacy, service: service, account: account),
           SecretStore.read(service: service, account: account) == legacy {
            defaults.removeObject(forKey: legacyKey)
        }
        return legacy
    }

    static func save(_ token: String, defaults: UserDefaults = .standard) {
        if SecretStore.write(token, service: service, account: account) {
            defaults.removeObject(forKey: legacyKey)
        } else {
            defaults.set(token, forKey: legacyKey)
        }
    }
}
