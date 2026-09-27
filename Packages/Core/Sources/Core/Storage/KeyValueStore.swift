import Foundation

// MARK: - KeyValueStore

/// Storage for small, non-sensitive preferences (cart ID, market choice, consent flags).
/// Backed by `UserDefaults` in the app and by memory in tests and previews.
///
/// Values are typed: a value stored as a string is not returned by `bool(forKey:)` and vice
/// versa. Setting `nil` removes the value. Because `set(nil, forKey:)` would be ambiguous
/// between the overloads, use `removeValue(forKey:)` to remove a value explicitly.
///
/// Never store secrets here; use `SecureStore`.
public protocol KeyValueStore: Sendable {
    /// Returns the data stored for `key`.
    func data(forKey key: String) -> Data?
    /// Stores `data` for `key`, or removes the value when `data` is `nil`.
    func set(_ data: Data?, forKey key: String)

    /// Returns the string stored for `key`.
    func string(forKey key: String) -> String?
    /// Stores `string` for `key`, or removes the value when `string` is `nil`.
    func set(_ string: String?, forKey key: String)

    /// Returns the Boolean stored for `key`, or `nil` when there is none (unlike
    /// `UserDefaults.bool(forKey:)`, which returns `false`).
    func bool(forKey key: String) -> Bool?
    /// Stores `bool` for `key`, or removes the value when `bool` is `nil`.
    func set(_ bool: Bool?, forKey key: String)

    /// Removes the value for `key`, whatever its type.
    func removeValue(forKey key: String)
}

// MARK: - Default removal

extension KeyValueStore {
    /// Removes the value for `key` by storing `nil` data, which by contract removes the value
    /// whatever its type. Conforming types may provide a more direct implementation.
    public func removeValue(forKey key: String) {
        set(Data?.none, forKey: key)
    }
}

// MARK: - Codable helpers

extension KeyValueStore {
    /// Decodes the JSON value stored for `key`.
    ///
    /// - Returns: `nil` if nothing is stored for `key`.
    /// - Throws: The `DecodingError` if the stored data is not a valid `T`.
    public func value<T: Decodable>(_ type: T.Type = T.self, forKey key: String) throws -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Stores `value` for `key` as JSON, or removes the value when `value` is `nil`.
    ///
    /// - Throws: The `EncodingError` if `value` cannot be encoded; the stored value is then
    ///   left unchanged.
    public func setValue(_ value: (some Encodable)?, forKey key: String) throws {
        guard let value else {
            removeValue(forKey: key)
            return
        }
        try set(JSONEncoder().encode(value), forKey: key)
    }
}

// MARK: - UserDefaultsStore

/// A `KeyValueStore` backed by a `UserDefaults` suite.
public final class UserDefaultsStore: KeyValueStore, @unchecked Sendable {
    // `@unchecked Sendable` is sound: the only stored property is an immutable reference to a
    // `UserDefaults` instance, and `UserDefaults` is documented as thread-safe (every method may
    // be called from any thread). The annotation is required because the Foundation overlays
    // do not declare `UserDefaults` as `Sendable`.

    private let defaults: UserDefaults

    /// Creates a store backed by `defaults`, `UserDefaults.standard` by default.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Creates a store backed by the suite `suiteName`, e.g. an app group shared with widgets.
    ///
    /// - Returns: `nil` if the suite cannot be created (for example for the app's own bundle
    ///   identifier or `NSGlobalDomain`).
    public convenience init?(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.init(defaults: defaults)
    }

    /// Returns the data stored for `key`.
    public func data(forKey key: String) -> Data? {
        defaults.object(forKey: key) as? Data
    }

    /// Stores or removes `data`.
    public func set(_ data: Data?, forKey key: String) {
        store(data, forKey: key)
    }

    /// Returns the string stored for `key`.
    public func string(forKey key: String) -> String? {
        defaults.object(forKey: key) as? String
    }

    /// Stores or removes `string`.
    public func set(_ string: String?, forKey key: String) {
        store(string, forKey: key)
    }

    /// Returns the Boolean stored for `key`.
    public func bool(forKey key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    /// Stores or removes `bool`.
    public func set(_ bool: Bool?, forKey key: String) {
        store(bool, forKey: key)
    }

    /// Removes the value for `key`.
    public func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }

    private func store(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - InMemoryKeyValueStore

/// A `KeyValueStore` that keeps values in memory, for tests and previews. Thread-safe.
public final class InMemoryKeyValueStore: KeyValueStore {
    private enum StoredValue: Sendable, Equatable {
        case data(Data)
        case string(String)
        case bool(Bool)
    }

    private let storage = Locked<[String: StoredValue]>([:])

    /// Creates an empty store.
    public init() {}

    /// Returns the data stored for `key`.
    public func data(forKey key: String) -> Data? {
        guard case let .data(data) = storage.withLock({ $0[key] }) else { return nil }
        return data
    }

    /// Stores or removes `data`.
    public func set(_ data: Data?, forKey key: String) {
        store(data.map(StoredValue.data), forKey: key)
    }

    /// Returns the string stored for `key`.
    public func string(forKey key: String) -> String? {
        guard case let .string(string) = storage.withLock({ $0[key] }) else { return nil }
        return string
    }

    /// Stores or removes `string`.
    public func set(_ string: String?, forKey key: String) {
        store(string.map(StoredValue.string), forKey: key)
    }

    /// Returns the Boolean stored for `key`.
    public func bool(forKey key: String) -> Bool? {
        guard case let .bool(bool) = storage.withLock({ $0[key] }) else { return nil }
        return bool
    }

    /// Stores or removes `bool`.
    public func set(_ bool: Bool?, forKey key: String) {
        store(bool.map(StoredValue.bool), forKey: key)
    }

    /// Removes the value for `key`.
    public func removeValue(forKey key: String) {
        store(nil, forKey: key)
    }

    /// Removes every value.
    public func removeAll() {
        storage.withLock { $0.removeAll() }
    }

    /// The keys that currently have a value.
    public var keys: Set<String> {
        Set(storage.value.keys)
    }

    private func store(_ value: StoredValue?, forKey key: String) {
        storage.withLock { $0[key] = value }
    }
}
