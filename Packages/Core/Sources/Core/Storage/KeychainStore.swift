#if canImport(Security)
import Foundation
import Security

/// A `SecureStore` backed by the iOS Keychain.
///
/// Items are generic passwords (`kSecClassGenericPassword`) identified by `service` and the
/// key as `kSecAttrAccount`. They are readable after the first unlock, never leave the device
/// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, excluded from backups) and never sync
/// through iCloud Keychain (`kSecAttrSynchronizable = false`).
///
/// Keychain services are thread-safe, so the store can be used from any thread. The calls can
/// block briefly; keep them off the main actor where possible.
public final class KeychainStore: SecureStore {
    /// The `kSecAttrService` all items of this store share.
    public let service: String
    /// The Keychain access group, or `nil` for the app's default group.
    public let accessGroup: String?

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - service: The `kSecAttrService` of all items, `de.karinex.app` by default.
    ///   - accessGroup: An access group shared with extensions, or `nil` for the default group.
    public init(service: String = "de.karinex.app", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - SecureStore

    /// Returns the data stored for `key`, or `nil` if there is none.
    ///
    /// - Throws: `SecureStoreError.unexpectedStatus` for Keychain failures, for example
    ///   `errSecInteractionNotAllowed` before the first unlock after a reboot.
    public func data(for key: String) throws -> Data? {
        var query = itemQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw SecureStoreError.unexpectedStatus(errSecDecode)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw SecureStoreError.unexpectedStatus(status)
        }
    }

    /// Stores `data` for `key`: updates an existing item, or adds a new one.
    ///
    /// The update also re-applies the accessibility class, so items written by older builds
    /// with a different class are migrated.
    public func set(_ data: Data, for key: String) throws {
        let query = itemQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
            if status == errSecDuplicateItem {
                // Another thread added the item between our update and add; update it instead.
                status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            }
        }
        guard status == errSecSuccess else {
            throw SecureStoreError.unexpectedStatus(status)
        }
    }

    /// Removes the item for `key`. A missing item is not an error.
    public func removeValue(for key: String) throws {
        try delete(itemQuery(for: key))
    }

    /// Removes every item of this store's `service` (and access group). Items of other
    /// services are not touched.
    public func removeAll() throws {
        try delete(serviceQuery())
    }

    // MARK: - Queries

    private func serviceQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func itemQuery(for key: String) -> [String: Any] {
        var query = serviceQuery()
        query[kSecAttrAccount as String] = key
        return query
    }

    private func delete(_ query: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.unexpectedStatus(status)
        }
    }
}
#endif
