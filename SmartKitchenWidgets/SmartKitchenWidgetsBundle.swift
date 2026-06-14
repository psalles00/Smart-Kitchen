import WidgetKit
import SwiftUI

/// Entry point for all Savoria widgets (Lock Screen + Home Screen).
///
/// The primary widget is ``AssistantWidget`` — it opens the app directly on the
/// assistant screen with the keyboard focused (via the
/// `smartkitchen://assistant` deep link).
@main
struct SmartKitchenWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AssistantWidget()
        AIChatWidget()
        FoodLogMenuWidget()
        FoodLogTextWidget()
        FoodLogVoiceWidget()
        FoodLogCameraWidget()
        FoodLogGalleryWidget()
        FoodLogLabelWidget()
        FoodLogManualWidget()
    }
}
