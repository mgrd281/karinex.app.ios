@testable import Core
import Foundation
import Testing

@Suite("FeatureFlags")
struct FeatureFlagsTests {
    @Test("Phase defaults switch everything off")
    func phaseDefaults() {
        for flag in FeatureFlag.allCases {
            #expect(!FeatureFlags.phaseDefaults.isEnabled(flag))
        }
    }

    @Test("setting(_:to:) returns a modified copy")
    func settingReturnsCopy() {
        let base = FeatureFlags.phaseDefaults
        let enabled = base.setting(.wishlist, to: true)
        #expect(enabled.isEnabled(.wishlist))
        #expect(!base.isEnabled(.wishlist))
        #expect(!enabled.setting(.wishlist, to: false).isEnabled(.wishlist))
    }

    @Test("Parses -kx.flag.<name> YES|NO launch argument pairs")
    func launchArguments() {
        let provider = StaticFeatureFlagProvider(launchArguments: [
            "/path/to/KARINEX",
            "-kx.uitesting",
            "-kx.flag.licenseVault", "YES",
            "-kx.flag.wishlist", "true",
            "-kx.flag.homeWidget", "1",
            "-kx.flag.remoteConfig", "NO",
        ], base: FeatureFlags(enabledFlags: [.remoteConfig, .liveActivity]))

        #expect(provider.isEnabled(.licenseVault))
        #expect(provider.isEnabled(.wishlist))
        #expect(provider.isEnabled(.homeWidget))
        #expect(!provider.isEnabled(.remoteConfig))
        #expect(provider.isEnabled(.liveActivity))
        #expect(!provider.isEnabled(.pushNotifications))
    }

    @Test("Ignores unknown flags, missing and invalid values; the last occurrence wins")
    func launchArgumentEdgeCases() {
        let flags = FeatureFlags.phaseDefaults.applyingLaunchArguments([
            "-kx.flag.unknownFlag", "YES",
            "-kx.flag.wishlist", "maybe",
            "-kx.flag.liveActivity", "YES",
            "-kx.flag.liveActivity", "NO",
            "-kx.flag.pushNotifications", "yes",
            "-kx.flag.homeWidget",
        ])
        #expect(flags.enabledFlags == [.pushNotifications])
    }

    @Test("Launch argument names are derived from the flag")
    func launchArgumentNames() {
        #expect(FeatureFlag.licenseVault.launchArgument == "-kx.flag.licenseVault")
    }

    @Test("Encodes as a name to Boolean object and ignores unknown names when decoding")
    func codable() throws {
        let flags = FeatureFlags(enabledFlags: [.wishlist])
        let data = try JSONEncoder().encode(flags)
        let object = try JSONDecoder().decode([String: Bool].self, from: data)
        #expect(object.count == FeatureFlag.allCases.count)
        #expect(object["wishlist"] == true)
        #expect(object["licenseVault"] == false)
        #expect(try JSONDecoder().decode(FeatureFlags.self, from: data) == flags)

        let remote = Data(#"{"licenseVault": true, "futureFlag": true, "wishlist": false}"#.utf8)
        #expect(try JSONDecoder().decode(FeatureFlags.self, from: remote) == FeatureFlags(enabledFlags: [.licenseVault]))
    }

    @Test("The static provider defaults to the phase defaults")
    func staticProviderDefaults() {
        let provider = StaticFeatureFlagProvider()
        #expect(provider.flags == .phaseDefaults)
    }
}

@Suite("LaunchEnvironment")
struct LaunchEnvironmentTests {
    @Test("Defaults to a normal launch")
    func defaults() {
        let environment = LaunchEnvironment(arguments: ["/path/to/KARINEX"])
        #expect(environment == LaunchEnvironment())
        #expect(!environment.isUITesting)
        #expect(!environment.resetState)
        #expect(environment.forcedAppearance == nil)
    }

    @Test("Parses UI test arguments")
    func parsesArguments() {
        let environment = LaunchEnvironment(arguments: [
            "/path/to/KARINEX", "-kx.uitesting", "-kx.reset", "-kx.appearance", "dark", "-kx.flag.wishlist", "YES",
        ])
        #expect(environment.isUITesting)
        #expect(environment.resetState)
        #expect(environment.forcedAppearance == .dark)
    }

    @Test("Switches accept an explicit YES or NO")
    func explicitSwitchValues() {
        let environment = LaunchEnvironment(arguments: ["-kx.uitesting", "YES", "-kx.reset", "NO", "-kx.appearance", "LIGHT"])
        #expect(environment.isUITesting)
        #expect(!environment.resetState)
        #expect(environment.forcedAppearance == .light)
    }

    @Test("Ignores invalid appearance values and a missing value")
    func invalidAppearance() {
        #expect(LaunchEnvironment(arguments: ["-kx.appearance", "sepia"]).forcedAppearance == nil)
        #expect(LaunchEnvironment(arguments: ["-kx.appearance"]).forcedAppearance == nil)
        #expect(LaunchEnvironment(arguments: ["-kx.appearance", "-kx.reset"]).forcedAppearance == nil)
        #expect(LaunchEnvironment(arguments: ["-kx.appearance", "-kx.reset"]).resetState)
    }

    @Test("Reads environment variables; arguments win")
    func environmentVariables() {
        let fromEnvironment = LaunchEnvironment(
            arguments: [],
            environment: ["KX_UI_TESTING": "1", "KX_RESET_STATE": "true", "KX_APPEARANCE": "light"]
        )
        #expect(fromEnvironment == LaunchEnvironment(isUITesting: true, resetState: true, forcedAppearance: .light))

        let overridden = LaunchEnvironment(
            arguments: ["-kx.reset", "NO", "-kx.appearance", "dark"],
            environment: ["KX_RESET_STATE": "1", "KX_APPEARANCE": "light"]
        )
        #expect(!overridden.resetState)
        #expect(overridden.forcedAppearance == .dark)
    }

    @Test("Reads the current process without crashing")
    func currentProcess() {
        let environment = LaunchEnvironment.current
        #expect(environment == LaunchEnvironment(processInfo: .processInfo))
    }

    @Test("Negative numbers are values, not flags")
    func negativeNumbers() {
        #expect(LaunchArguments.value(after: "-offset", in: ["-offset", "-5"]) == "-5")
        #expect(!LaunchArguments.isFlag("-5"))
        #expect(LaunchArguments.isFlag("-kx.reset"))
        #expect(!LaunchArguments.isFlag("-"))
    }
}
