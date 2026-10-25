import Foundation

/// Helpers for reading `-key value` style launch arguments, as passed by Xcode schemes and
/// `XCUIApplication.launchArguments`.
enum LaunchArguments {
    /// Returns the argument that follows `flag`, if `flag` is present and followed by a value
    /// that is not itself a flag. The last occurrence wins.
    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.lastIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        let value = arguments[valueIndex]
        return isFlag(value) ? nil : value
    }

    /// Returns whether `flag` is switched on: present on its own, or followed by a truthy value
    /// (`YES`, `true`, `1`). A following falsy value (`NO`, `false`, `0`) switches it off.
    static func isSwitchOn(_ flag: String, in arguments: [String]) -> Bool {
        guard arguments.contains(flag) else { return false }
        guard let value = value(after: flag, in: arguments) else { return true }
        return parseBool(value) ?? true
    }

    /// Parses `YES`/`NO`, `true`/`false` and `1`/`0` (case-insensitive).
    static func parseBool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "yes", "true", "1": true
        case "no", "false", "0": false
        default: nil
        }
    }

    /// Whether `argument` looks like a flag (`-name`) rather than a value. Negative numbers
    /// are values.
    static func isFlag(_ argument: String) -> Bool {
        guard argument.hasPrefix("-"), argument.count > 1 else { return false }
        let second = argument[argument.index(after: argument.startIndex)]
        return !second.isNumber
    }
}
