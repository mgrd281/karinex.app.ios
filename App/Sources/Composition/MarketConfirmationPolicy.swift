import Core
import Foundation

// MARK: - MarketConfirmationPolicy

/// Decides whether the one-time market confirmation sheet may appear.
///
/// In normal runs it does, once after the first market resolution. UI test runs
/// (`-kx.uitesting`) skip it so every test starts on the Start tab, unless the test passes
/// `-kx.market.confirm YES` to check the sheet itself.
enum MarketConfirmationPolicy {
    /// Launch argument that shows the sheet in UI test runs: `-kx.market.confirm YES`.
    static let argument = "-kx.market.confirm"

    /// Whether the sheet may appear for a process launched with `launchEnvironment` and
    /// `arguments` (including the executable path at index 0).
    static func isEnabled(launchEnvironment: LaunchEnvironment, arguments: [String]) -> Bool {
        guard launchEnvironment.isUITesting else { return true }
        guard let index = arguments.lastIndex(of: argument) else { return false }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return true }
        switch arguments[valueIndex].lowercased() {
        case "yes", "true", "1":
            return true
        case "no", "false", "0":
            return false
        default:
            // Another flag follows: the argument stands on its own and switches the sheet on.
            return arguments[valueIndex].hasPrefix("-")
        }
    }
}
