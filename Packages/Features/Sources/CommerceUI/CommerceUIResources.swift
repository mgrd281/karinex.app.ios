import Foundation

// MARK: - CommerceUIResources

/// Access to the resources of the CommerceUI module.
public enum CommerceUIResources {
    /// The bundle that holds the module's String Catalog.
    ///
    /// Views resolve their strings with `bundle: .module`; tests use this accessor to resolve
    /// them in a specific language through one of its `.lproj` folders.
    public static var bundle: Bundle {
        .module
    }
}
