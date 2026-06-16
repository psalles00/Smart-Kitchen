import SwiftUI

// MARK: - Notifications relayed from the shared-import host to ContentView.
//
// The shared-import sheet is hosted at the scene root (outside ContentView's
// `.id(cloudSync.containerID)` rebuild boundary) so that container swaps
// during launch never dismiss it. Because of that, action callbacks that
// need to mutate ContentView state (switch tabs, navigate to imported
// recipe, open assistant with prefill) are forwarded via NotificationCenter.
extension Notification.Name {
    /// User chose "Salvar alimento" on a shared image. ContentView should
    /// switch to the Nutrição tab — `SharedFoodCaptureInbox.shared` already
    /// holds the captured image.
    static let shareImportRouteToNutrients = Notification.Name("com.smartkitchen.shareImport.routeToNutrients")
    /// User chose "Abrir no assistente" on a shared link/text. `userInfo["prefill"]`
    /// carries the prompt to inject into the assistant chat.
    static let shareImportOpenAssistant = Notification.Name("com.smartkitchen.shareImport.openAssistant")
    /// A recipe was saved through the shared-import host. `userInfo["recipeID"]`
    /// is the new recipe's `UUID` — ContentView navigates the Receitas tab.
    static let shareImportRecipeSaved = Notification.Name("com.smartkitchen.shareImport.recipeSaved")
}

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
                    RecipeImportHostView(initialSource: source) { recipeID in
                        inbox.clear()
                        NotificationCenter.default.post(
                            name: .shareImportRecipeSaved,
                            object: nil,
                            userInfo: ["recipeID": recipeID]
                        )
                    }
                    .modelContainer(CloudSyncService.shared.container)
                    #if os(iOS)
                    .forceLightStatusBar()
                    #endif
                }
            }
    }
}

/// Hosts the shared-import (Share Extension) flow at the scene root, OUTSIDE
/// ContentView's `.id(cloudSync.containerID)` rebuild boundary. Without this
/// hoist the sheet would be torn down whenever CloudSync swaps the
/// `ModelContainer` after launch — exactly the moment the user just tapped
/// "Compartilhar" from another app — making the import modal "open and
/// immediately close." See `Notification.Name.shareImport*` above for the
/// callbacks routed back to ContentView.
struct SharedImportInboxHost: ViewModifier {

    private enum Presentation: Identifiable, Equatable {
        case recipe(token: String, source: RecipeImportSource)
        case actions(SharedImportItem)

        var id: String {
            switch self {
            case .recipe(let token, _):
                return "\(token)-recipe"
            case .actions(let item):
                return "\(item.id)-actions"
            }
        }

        var token: String {
            switch self {
            case .recipe(let token, _):
                return token
            case .actions(let item):
                return item.id
            }
        }
    }

    let isPresentationEnabled: Bool

    @State private var inbox = SharedImportInbox.shared
    @State private var activePresentation: Presentation?
    @State private var activeToken: String?
    /// Tracks the recipe id saved from inside the host so we can post it on
    /// dismissal (avoids racing the sheet-dismiss transaction).
    @State private var pendingSavedRecipeID: UUID?

    func body(content: Content) -> some View {
        content
            .sheet(item: $activePresentation, onDismiss: handleDismiss) { presentation in
                sheetBody(for: presentation)
            }
            .onAppear {
                presentPendingItemIfPossible(trigger: "onAppear")
            }
            .onChange(of: inbox.pendingItem?.id) { _, newValue in
                guard let token = newValue,
                      let pendingItem = inbox.pendingItem,
                      pendingItem.id == token else {
                    if newValue == nil {
                        RecipeImportLogger.info("shared-import host pendingItem cleared")
                    }
                    return
                }
                RecipeImportLogger.info("shared-import host pendingItem detected token=\(token) kind=\(pendingItem.kind.rawValue)")
                presentPendingItemIfPossible(item: pendingItem, trigger: "pending item change")
            }
            .onChange(of: isPresentationEnabled) { _, newValue in
                guard newValue else { return }
                presentPendingItemIfPossible(trigger: "presentation gate enabled")
            }
    }

    @ViewBuilder
    private func sheetBody(for presentation: Presentation) -> some View {
        switch presentation {
        case .recipe(_, let source):
            RecipeImportHostView(initialSource: source) { recipeID in
                RecipeImportLogger.info("shared-import host recipe saved id=\(recipeID.uuidString)")
                pendingSavedRecipeID = recipeID
                activePresentation = nil
            }
            .modelContainer(CloudSyncService.shared.container)
            #if os(iOS)
            .forceLightStatusBar()
            #endif

        case .actions(let item):
            SharedImportActionView(
                item: item,
                onReviewRecipe: {
                    guard let source = item.recipeImportSource else {
                        RecipeImportLogger.error("shared-import host onReviewRecipe missing source kind=\(item.kind.rawValue)")
                        activePresentation = nil
                        return
                    }
                    RecipeImportLogger.info("shared-import host swap to RecipeImportHostView \(RecipeImportLogger.sourceSummary(source))")
                    activePresentation = .recipe(token: item.id, source: source)
                },
                onRegisterFood: item.foodCapture == nil ? nil : {
                    if let capture = item.foodCapture {
                        SharedFoodCaptureInbox.shared.capture(capture)
                    }
                    NotificationCenter.default.post(name: .shareImportRouteToNutrients, object: nil)
                    activePresentation = nil
                },
                onAskAssistant: item.assistantPrefill == nil ? nil : {
                    if let prefill = item.assistantPrefill {
                        NotificationCenter.default.post(
                            name: .shareImportOpenAssistant,
                            object: nil,
                            userInfo: ["prefill": prefill]
                        )
                    }
                    activePresentation = nil
                },
                onDismiss: {
                    activePresentation = nil
                }
            )
        }
    }

    private func present(_ item: SharedImportItem) {
        activeToken = item.id
        // For URL shares we skip the action chooser and go straight to the
        // Recipe Import host (matches the previous behavior).
        if item.kind == .url, let source = item.recipeImportSource {
            RecipeImportLogger.info("shared-import host prepared direct RecipeImportHostView token=\(item.id) \(RecipeImportLogger.sourceSummary(source))")
            activePresentation = .recipe(token: item.id, source: source)
        } else {
            activePresentation = .actions(item)
        }
    }

    private func presentPendingItemIfPossible(item: SharedImportItem? = nil, trigger: String) {
        guard activePresentation == nil else { return }

        let pendingItem = item ?? inbox.pendingItem
        guard let pendingItem else { return }

        guard isPresentationEnabled else {
            RecipeImportLogger.info("shared-import host deferred presentation token=\(pendingItem.id) trigger=\(trigger)")
            return
        }

        RecipeImportLogger.info("shared-import host presenting token=\(pendingItem.id) trigger=\(trigger)")
        present(pendingItem)
    }

    private func handleDismiss() {
        let token = activeToken
        let savedRecipeID = pendingSavedRecipeID
        pendingSavedRecipeID = nil
        activeToken = nil

        if let token {
            inbox.clear(token: token)
        }

        if let savedRecipeID {
            NotificationCenter.default.post(
                name: .shareImportRecipeSaved,
                object: nil,
                userInfo: ["recipeID": savedRecipeID]
            )
        }

        // If a different shared payload arrived while the previous sheet was
        // dismissing, present it on the next runloop tick.
        if let next = inbox.pendingItem, next.id != token {
            Task { @MainActor in
                    presentPendingItemIfPossible(item: next, trigger: "post-dismiss pending item")
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

    /// Presents the Share-Extension import flow at the scene root. MUST be
    /// applied OUTSIDE any `.id(...)` boundary that can rebuild on launch
    /// (e.g. `cloudSync.containerID`); otherwise a container swap
    /// immediately after the share-extension deep link will dismiss the
    /// freshly presented sheet.
    func sharedImportInboxHost(isPresentationEnabled: Bool = true) -> some View {
        modifier(SharedImportInboxHost(isPresentationEnabled: isPresentationEnabled))
    }
}

struct SharedImportActionView: View {
    let item: SharedImportItem
    let onReviewRecipe: () -> Void
    let onRegisterFood: (() -> Void)?
    let onAskAssistant: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    previewCard

                    VStack(spacing: 12) {
                        actionCard(
                            icon: recipeActionIcon,
                            title: recipeActionTitle,
                            subtitle: recipeActionSubtitle,
                            accent: PageTheme.recipes.accentColor,
                            action: onReviewRecipe
                        )

                        if let onRegisterFood {
                            actionCard(
                                icon: "fork.knife.circle.fill",
                                title: String(localized: "Salvar alimento"),
                                subtitle: String(localized: "Guarde esta imagem como referência para o módulo de Nutrientes."),
                                accent: PageTheme.nutrients.accentColor,
                                action: onRegisterFood
                            )
                        }

                        if let onAskAssistant {
                            actionCard(
                                icon: "sparkles",
                                title: String(localized: "Abrir no assistente"),
                                subtitle: String(localized: "Usar o conteúdo compartilhado como contexto na conversa com a IA."),
                                accent: PageTheme.home.accentColor,
                                action: onAskAssistant
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .modalNavigationTitle(String(localized: "O que você quer fazer?"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .tint(.secondary)
                }
                #else
                ToolbarItem {
                    Button("Fechar") {
                        onDismiss()
                    }
                }
                #endif
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.displayTitle)
                .font(.headline.weight(.semibold))
            Text(item.detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var previewCard: some View {
        switch item.kind {
        case .image:
            if let imageData = item.imageData, let image = platformImage(from: imageData) {
                Group {
                    #if os(iOS)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                    #else
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                    #endif
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()
                .clipShape(.rect(cornerRadius: 18))
            }

        case .video:
            infoCard(icon: "video.fill", title: String(localized: "Vídeo recebido"), subtitle: item.filename ?? item.mediaFileURL?.lastPathComponent ?? String(localized: "Vídeo compartilhado"))

        case .url:
            infoCard(icon: "link", title: String(localized: "Link recebido"), subtitle: item.url?.absoluteString ?? "")

        case .text:
            infoCard(icon: "text.alignleft", title: String(localized: "Texto recebido"), subtitle: item.text ?? "")
        }
    }

    private var recipeActionTitle: String {
        switch item.kind {
        case .image:
            return String(localized: "Identificar receita")
        case .video:
            return String(localized: "Revisar receita do vídeo")
        case .url, .text:
            return String(localized: "Revisar como receita")
        }
    }

    private var recipeActionSubtitle: String {
        switch item.kind {
        case .image:
            return String(localized: "Extrair ingredientes e etapas da imagem e abrir a revisão antes de salvar.")
        case .video:
            return String(localized: "Transcrever o vídeo, estruturar a receita e abrir a revisão antes de salvar.")
        case .url:
            return String(localized: "Importar o link compartilhado e abrir a revisão da receita.")
        case .text:
            return String(localized: "Organizar o texto compartilhado em ingredientes e modo de preparo.")
        }
    }

    private var recipeActionIcon: String {
        switch item.kind {
        case .image:
            return "photo.badge.magnifyingglass"
        case .video:
            return "play.rectangle.fill"
        case .url:
            return "link.badge.plus"
        case .text:
            return "text.badge.plus"
        }
    }

    private func actionCard(
        icon: String,
        title: String,
        subtitle: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 50, height: 50)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 18))
    }

    private func platformImage(from data: Data) -> PlatformImage? {
        #if os(iOS)
        return UIImage(data: data)
        #else
        return NSImage(data: data)
        #endif
    }
}
