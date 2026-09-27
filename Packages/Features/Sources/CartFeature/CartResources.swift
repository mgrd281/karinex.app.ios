import Foundation

// MARK: - CartResources

/// Access to the resources of the CartFeature module.
enum CartResources {
    /// The bundle that holds the module's String Catalog.
    ///
    /// Views resolve their strings with `bundle: .module`; tests use this accessor to resolve
    /// them in a specific language through one of its `.lproj` folders.
    static var bundle: Bundle {
        .module
    }
}
