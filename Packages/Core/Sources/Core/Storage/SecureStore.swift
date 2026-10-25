import Foundation

// MARK: - SecureStore

/// Storage for secrets: customer tokens, cached license keys. Backed by the Keychain in the
/// app (`KeychainStore`) and by memory in tests and previews (`InMemorySecureStore`).
///
/// Implementations are synchronous and thread-safe. Keychain calls can block briefly, so call
/// them off the main actor.
public protocol SecureStore: Sendable {
    /// Returns the data stored for `key`, or `nil` if there is none.
    func data(for key: String) throws -> Data?

    /// Stores `data` for `key`, replacing any existing value.
    func set(_ data: Data, for key: String) throws

    /// Removes the value for `key`. Removing a missing value is not an error.
    func removeValue(for key: String) throws

    /// Removes every value this store owns (for example on logout or account deletion).
    func removeAll() throws
}

// MARK: - Codable helpers

extension SecureStore {
    /// Decodes the JSON value stored for `key`.
    ///
    /// - Returns: `nil` if nothing is stored for `key`.
    /// - Throws: `SecureStoreError.decoding` if the stored data is not a valid `T`, or the
    ///   store's own errors.
    public func value<T: Decodable>(_ type: T.Type = T.self, for key: String) throws -> T? {
        guard let data = try data(for: key) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SecureStoreError.decoding
        }
    }

    /// Stores `value` for `key` as JSON.
    ///
    /// - Throws: `SecureStoreError.encoding` if `value` cannot be encoded, or the store's own errors.
    public func setValue(_ value: some Encodable, for key: String) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw SecureStoreError.encoding
        }
        try set(data, for: key)
    }

    /// Returns the UTF-8 string stored for `key`.
    ///
    /// - Throws: `SecureStoreError.decoding` if the stored data is not valid UTF-8.
    public func string(for key: String) throws -> String? {
        guard let data = try data(for: key) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else {
            throw SecureStoreError.decoding
        }
        return string
    }

    /// Stores `string` for `key` as UTF-8.
    public func setString(_ string: String, for key: String) throws {
        try set(Data(string.utf8), for: key)
    }
}

// MARK: - SecureStoreError

/// Errors of `SecureStore` implementations.
public enum SecureStoreError: Error, Sendable, Equatable {
    /// The Keychain returned an unexpected `OSStatus`.
    case unexpectedStatus(Int32)
    /// A value could not be encoded.
    case encoding
    /// Stored data could not be decoded into the requested type.
    case decoding
}

// MARK: - InMemorySecureStore

/// A `SecureStore` that keeps values in memory, for tests and previews. Thread-safe.
public final class InMemorySecureStore: SecureStore {
    private let storage: Locked<[String: Data]>

    /// Creates a store pre-filled with `values`.
    public init(values: [String: Data] = [:]) {
        storage = Locked(values)
    }

    /// Returns the data stored for `key`.
    public func data(for key: String) throws -> Data? {
        storage.withLock { $0[key] }
    }

    /// Stores `data` for `key`.
    public func set(_ data: Data, for key: String) throws {
        storage.withLock { $0[key] = data }
    }

    /// Removes the value for `key`.
    public func removeValue(for key: String) throws {
        storage.withLock { _ = $0.removeValue(forKey: key) }
    }

    /// Removes every value.
    public func removeAll() throws {
        storage.withLock { $0.removeAll() }
    }

    /// The keys that currently have a value.
    public var keys: Set<String> {
        Set(storage.value.keys)
    }
}
