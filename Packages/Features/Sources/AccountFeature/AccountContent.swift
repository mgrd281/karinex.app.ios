import Foundation

// MARK: - AccountAppInfo

/// The version of the running app as shown in the "Über die App" section, e.g. "0.1.0 (1)".
struct AccountAppInfo: Equatable, Sendable {
    /// The marketing version (`CFBundleShortVersionString`), trimmed.
    let version: String
    /// The build number (`CFBundleVersion`), trimmed.
    let build: String

    /// Creates the info from the raw bundle values; surrounding whitespace is removed.
    init(version: String, build: String) {
        self.version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        self.build = build.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Version and build in the conventional Apple form "0.1.0 (1)". A missing part is left out;
    /// the result is empty only when both are missing.
    var summary: String {
        switch (version.isEmpty, build.isEmpty) {
        case (false, false): "\(version) (\(build))"
        case (false, true): version
        case (true, false): build
        case (true, true): ""
        }
    }
}

// MARK: - AccountBenefit

/// The benefits of a customer account, shown to signed-out users in display order
/// (PROMPT.md section 6.7).
enum AccountBenefit: String, CaseIterable, Identifiable, Sendable {
    /// Orders and invoices at any time.
    case ordersAndInvoices
    /// License keys stored securely on this device (Keychain, device only).
    case licenseKeys
    /// Faster checkout with the account's saved details.
    case fasterCheckout

    /// Stable identity for `ForEach`.
    var id: String {
        rawValue
    }

    /// Decorative SF Symbol leading the benefit.
    var systemImage: String {
        switch self {
        case .ordersAndInvoices: "doc.text"
        case .licenseKeys: "key"
        case .fasterCheckout: "bolt"
        }
    }

    /// The benefit in the user's language.
    var text: String {
        text(in: AccountResources.bundle)
    }

    /// The benefit resolved against `bundle`: the module bundle, or one of its `.lproj` folders.
    func text(in bundle: Bundle) -> String {
        String(localized: textKey, bundle: bundle)
    }

    private var textKey: String.LocalizationValue {
        switch self {
        case .ordersAndInvoices: "account.benefit.orders"
        case .licenseKeys: "account.benefit.keys"
        case .fasterCheckout: "account.benefit.checkout"
        }
    }
}
