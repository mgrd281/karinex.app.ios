import Foundation

// MARK: - ProductFeatureResources

/// Access to the resources of the ProductFeature module.
public enum ProductFeatureResources {
    /// The bundle that holds the module's String Catalog.
    ///
    /// Views resolve their strings with `bundle: .module`; tests use this accessor to resolve
    /// them in a specific language through one of its `.lproj` folders.
    public static var bundle: Bundle {
        .module
    }
}
