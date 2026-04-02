import SwiftUI

/// Reusable toolbar button that triggers an external action when tapped.
struct SettingsButton: View {
    let onTap: () -> Void

    init(onTap: @escaping () -> Void = {}) {
        self.onTap = onTap
    }

    var body: some View {
        GlassButtonGroup {
            GlassGroupButton(systemImage: "gearshape", action: onTap)
        }
    }
}
