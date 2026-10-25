import SwiftUI
import WidgetKit

// MARK: - KARINEXWidgetsBundle

/// The widget extension: the bestseller widget and the license delivery Live Activity.
@main
struct KARINEXWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BestsellerWidget()
        LicenseDeliveryLiveActivity()
    }
}
