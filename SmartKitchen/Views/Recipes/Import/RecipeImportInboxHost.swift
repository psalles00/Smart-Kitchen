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

    @State private var inbox = SharedImportInbox.shared
    @State private var activeItem: SharedImportItem?
    @State private var recipeSource: RecipeImportSource?
    @State private var isPresented: Bool = false
    /// Tracks the recipe id saved from inside the host so we can post it on
    /// dismissal (avoids racing the sheet-dismiss transaction).
    @State private var pendingSavedRecipeID: UUID?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: handleDismiss) {
                sheetBody
            }
            .onAppear {
                guard !isPresented, let pendingItem = inbox.pendingItem else { return }
                RecipeImportLogger.info("shared-import host presenting existing pending item token=\(pendingItem.id)")
                present(pendingItem)
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
                present(pendingItem)
            }
    }

    @ViewBuilder
    private var sheetBody: some View {
        if let source = recipeSource {
            RecipeImportHostView(initialSource: source) { recipeID in
                RecipeImportLogger.info("shared-import host recipe saved id=\(recipeID.uuidString)")
                pendingSavedRecipeID = recipeID
                isPresented = false
            }
            .modelContainer(CloudSyncService.shared.container)
            #if os(iOS)
            .forceLightStatusBar()
            #endif
        } else if let item = activeItem {
            SharedImportActionView(
                item: item,
                onReviewRecipe: {
                    guard let source = item.recipeImportSource else {
                        RecipeImportLogger.error("shared-import host onReviewRecipe missing source kind=\(item.kind.rawValue)")
                        isPresented = false
                        return
                    }
                    RecipeImportLogger.info("shared-import host swap to RecipeImportHostView \(RecipeImportLogger.sourceSummary(source))")
                    recipeSource = source
                },
                onRegisterFood: item.foodCapture == nil ? nil : {
                    if let capture = item.foodCapture {
                        SharedFoodCaptureInbox.shared.capture(capture)
                    }
                    NotificationCenter.default.post(name: .shareImportRouteToNutrients, object: nil)
                    isPresented = false
                },
                onAskAssistant: item.assistantPrefill == nil ? nil : {
                    if let prefill = item.assistantPrefill {
                        NotificationCenter.default.post(
                            name: .shareImportOpenAssistant,
                            object: nil,
                            userInfo: ["prefill": prefill]
                        )
                    }
                    isPresented = false
                },
                onDismiss: {
                    isPresented = false
                }
            )
        } else {
            // Fallback: this should never present, but if it ever does we
            // show an explicit error rather than silently auto-dismissing,
            // which previously masked the regression.
            NavigationStack {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("Não foi possível abrir o compartilhamento")
                        .font(.headline)
                    Text("O conteúdo compartilhado ficou indisponível antes da importação começar. Tente compartilhar novamente.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Fechar") { isPresented = false }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .onAppear {
                    RecipeImportLogger.error("shared-import host presented without payload")
                }
            }
        }
    }

    private func present(_ item: SharedImportItem) {
        activeItem = item
        // For URL shares we skip the action chooser and go straight to the
        // Recipe Import host (matches the previous behavior).
        if item.kind == .url, let source = item.recipeImportSource {
            recipeSource = source
        } else {
            recipeSource = nil
        }
        isPresented = true
    }

    private func handleDismiss() {
        let token = activeItem?.id
        let savedRecipeID = pendingSavedRecipeID
        pendingSavedRecipeID = nil
        recipeSource = nil
        activeItem = nil

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
                present(next)
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
    func sharedImportInboxHost() -> some View {
        modifier(SharedImportInboxHost())
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
                                title: "Salvar alimento",
                                subtitle: "Guarde esta imagem como referência para o módulo de Nutrientes.",
                                accent: PageTheme.nutrients.accentColor,
                                action: onRegisterFood
                            )
                        }

                        if let onAskAssistant {
                            actionCard(
                                icon: "sparkles",
                                title: "Abrir no assistente",
                                subtitle: "Usar o conteúdo compartilhado como contexto na conversa com a IA.",
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
            .modalNavigationTitle("O que você quer fazer?")
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
            infoCard(icon: "video.fill", title: "Vídeo recebido", subtitle: item.filename ?? item.mediaFileURL?.lastPathComponent ?? "Vídeo compartilhado")

        case .url:
            infoCard(icon: "link", title: "Link recebido", subtitle: item.url?.absoluteString ?? "")

        case .text:
            infoCard(icon: "text.alignleft", title: "Texto recebido", subtitle: item.text ?? "")
        }
    }

    private var recipeActionTitle: String {
        switch item.kind {
        case .image:
            return "Identificar receita"
        case .video:
            return "Revisar receita do vídeo"
        case .url, .text:
            return "Revisar como receita"
        }
    }

    private var recipeActionSubtitle: String {
        switch item.kind {
        case .image:
            return "Extrair ingredientes e etapas da imagem e abrir a revisão antes de salvar."
        case .video:
            return "Transcrever o vídeo, estruturar a receita e abrir a revisão antes de salvar."
        case .url:
            return "Importar o link compartilhado e abrir a revisão da receita."
        case .text:
            return "Organizar o texto compartilhado em ingredientes e modo de preparo."
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
