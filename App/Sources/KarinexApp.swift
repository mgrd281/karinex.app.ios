import SwiftUI

// MARK: - KarinexApp

/// The KARINEX app.
///
/// Builds the composition root once per process and injects it into the view hierarchy. Launch
/// switches (`-kx.uitesting`, `-kx.reset`, `-kx.appearance`, `-kx.flag.<name>`) are read by
/// `AppContainer.live()`.
@main
struct KarinexApp: App {
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
        }
    }
}
