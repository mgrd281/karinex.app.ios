import Core
import SwiftUI

// MARK: - Forced appearance

extension LaunchEnvironment.Appearance {
    /// The SwiftUI color scheme for an appearance forced with `-kx.appearance light|dark`.
    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}
