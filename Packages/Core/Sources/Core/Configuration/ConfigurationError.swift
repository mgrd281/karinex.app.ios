import Foundation

/// A problem with the build-time configuration injected into the app's `Info.plist`.
///
/// Configuration values come from the `.xcconfig` files (see `Config/Base.xcconfig`). A
/// missing or unresolved value almost always means a build setting was not defined, for
/// example because `Config/Secrets.xcconfig` is missing on a CI machine.
public enum ConfigurationError: Error, Sendable, Equatable {
    /// A required key is absent, empty, or still contains an unresolved `$(VARIABLE)`.
    case missingValue(key: String)

    /// A key is present but its value does not have the expected format.
    ///
    /// `value` is the offending value, safe to log: for the secret keys
    /// (`KXStorefrontAccessToken`, `KXCustomerAccountClientID`) it is `<redacted>`.
    case invalidValue(key: String, value: String)
}

// MARK: - CustomStringConvertible

extension ConfigurationError: CustomStringConvertible {
    /// A developer-facing description suitable for logs.
    public var description: String {
        switch self {
        case let .missingValue(key):
            "Missing configuration value for Info.plist key \(key)"
        case let .invalidValue(key, value):
            "Invalid configuration value for Info.plist key \(key): \"\(value)\""
        }
    }
}
