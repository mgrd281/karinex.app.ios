import Foundation

// MARK: - SearchResources

/// Access to the resources of the SearchFeature module.
enum SearchResources {
    /// The bundle that holds the module's String Catalog.
    ///
    /// Views resolve their strings with `bundle: .module`; tests use this accessor to resolve
    /// them in a specific language through one of its `.lproj` folders.
    static var bundle: Bundle {
        .module
    }
}
