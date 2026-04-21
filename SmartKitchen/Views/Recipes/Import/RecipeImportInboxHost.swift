import SwiftUI

/// View modifier that presents the Recipe Import flow automatically whenever
/// `RecipeImportInbox.shared.pendingSource` becomes non-nil. Attach once at the
/// scene root (applied in `SmartKitchenApp`).
struct RecipeImportInboxHost: ViewModifier {

    @State private var inbox = RecipeImportInbox.shared

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(
                    get: { inbox.pendingSource != nil },
                    set: { newValue in if !newValue { inbox.clear() } }
                )
            ) {
                if let source = inbox.pendingSource {
                    RecipeImportHostView(initialSource: source) { _ in
                        inbox.clear()
                    }
                    .modelContainer(CloudSyncService.shared.container)
                    #if os(iOS)
                    .forceLightStatusBar()
                    #endif
                }
            }
    }
}

extension View {
    /// Presents the Recipe Import host whenever a new source arrives via the
    /// `RecipeImportInbox` (URL schemes, share extension, deep links).
    func recipeImportInboxHost() -> some View {
        modifier(RecipeImportInboxHost())
    }
}
