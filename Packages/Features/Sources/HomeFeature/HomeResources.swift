import Foundation

// MARK: - HomeResources

/// Access to the resources of the HomeFeature module.
enum HomeResources {
    /// The bundle that holds the module's String Catalog.
    ///
    /// Views resolve their strings with `bundle: .module`. Content types resolve through this
    /// accessor, and tests pass one of its `.lproj` folders to check a specific language.
    static var bundle: Bundle {
        .module
    }
}
