import Foundation

/// Launch-time switches for UI tests and development, read from the process arguments and
/// environment.
///
/// | Argument | Environment variable | Effect |
/// | --- | --- | --- |
/// | `-kx.uitesting` | `KX_UI_TESTING=1` | `isUITesting`: deterministic UI (no onboarding sheets, no network-dependent surprises) |
/// | `-kx.reset` | `KX_RESET_STATE=1` | `resetState`: wipe preferences, consent and Keychain items at launch |
/// | `-kx.appearance light` / `dark` | `KX_APPEARANCE=light` / `dark` | `forcedAppearance`: force a color scheme |
///
/// Switch arguments may be followed by `YES`/`NO` (`-kx.reset NO` switches it off). Arguments
/// win over environment variables.
public struct LaunchEnvironment: Sendable, Equatable {
    // MARK: - Types

    /// A color scheme forced at launch.
    public enum Appearance: String, Sendable, CaseIterable {
        /// Light mode.
        case light
        /// Dark mode.
        case dark
    }

    // MARK: - Argument and variable names

    /// Launch argument that marks a UI test run.
    public static let uiTestingArgument = "-kx.uitesting"
    /// Launch argument that resets persisted state at launch.
    public static let resetArgument = "-kx.reset"
    /// Launch argument that forces an appearance; followed by `light` or `dark`.
    public static let appearanceArgument = "-kx.appearance"
    /// Environment variable equivalent of `uiTestingArgument`.
    public static let uiTestingVariable = "KX_UI_TESTING"
    /// Environment variable equivalent of `resetArgument`.
    public static let resetVariable = "KX_RESET_STATE"
    /// Environment variable equivalent of `appearanceArgument`.
    public static let appearanceVariable = "KX_APPEARANCE"

    // MARK: - Properties

    /// Whether the app runs under UI tests.
    public var isUITesting: Bool
    /// Whether persisted state (preferences, consent, Keychain items) is wiped at launch.
    public var resetState: Bool
    /// A forced color scheme, or `nil` to follow the system.
    public var forcedAppearance: Appearance?

    // MARK: - Init

    /// Creates an environment from explicit values (all off by default).
    public init(isUITesting: Bool = false, resetState: Bool = false, forcedAppearance: Appearance? = nil) {
        self.isUITesting = isUITesting
        self.resetState = resetState
        self.forcedAppearance = forcedAppearance
    }

    /// Parses `arguments` (including the executable path at index 0, as in
    /// `ProcessInfo.arguments`) and `environment`.
    public init(arguments: [String], environment: [String: String] = [:]) {
        isUITesting = Self.switchValue(
            argument: Self.uiTestingArgument,
            variable: Self.uiTestingVariable,
            arguments: arguments,
            environment: environment
        )
        resetState = Self.switchValue(
            argument: Self.resetArgument,
            variable: Self.resetVariable,
            arguments: arguments,
            environment: environment
        )
        let appearanceValue = LaunchArguments.value(after: Self.appearanceArgument, in: arguments)
            ?? environment[Self.appearanceVariable]
        forcedAppearance = appearanceValue.flatMap { value in
            Appearance(rawValue: value.trimmingCharacters(in: .whitespaces).lowercased())
        }
    }

    /// Parses the arguments and environment of `processInfo`.
    public init(processInfo: ProcessInfo) {
        self.init(arguments: processInfo.arguments, environment: processInfo.environment)
    }

    /// The environment of the current process.
    public static var current: LaunchEnvironment {
        LaunchEnvironment(processInfo: .processInfo)
    }

    // MARK: - Private

    private static func switchValue(
        argument: String,
        variable: String,
        arguments: [String],
        environment: [String: String]
    ) -> Bool {
        if arguments.contains(argument) {
            return LaunchArguments.isSwitchOn(argument, in: arguments)
        }
        guard let value = environment[variable] else { return false }
        return LaunchArguments.parseBool(value) ?? false
    }
}
