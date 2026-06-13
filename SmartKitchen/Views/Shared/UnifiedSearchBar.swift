import SwiftUI

// MARK: - Unified Search Bar

/// Liquid Glass search bar displayed in the shader area.
/// Uses `.glassEffect()` on iOS 26+, falls back to `.ultraThinMaterial`.
struct UnifiedSearchBar: View {
    @ObservedObject var state: SearchBarState
    let onAction: (CommandBarAction) -> Void
    let onOpenRecipeImport: (RecipeImportLaunchMode) -> Void
    let onOpenFoodCameraDirect: () -> Void
    let onOpenFoodGalleryDirect: () -> Void
    private let chromeHeight: CGFloat = 46

    @FocusState private var isFocused: Bool

    private var isEmpty: Bool {
        state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasTypedText: Bool {
        !state.searchText.isEmpty
    }

    private var shouldCollapseQuickActions: Bool {
        isFocused || hasTypedText
    }

    private func requestFocus() {
        if state.isVisible {
            state.focusTrigger += 1
        } else {
            state.reveal(mode: state.mode)
        }
    }

    @ViewBuilder
    private func applyMacAssistantForegroundOverride<Content: View>(to content: Content) -> some View {
#if os(macOS)
        content
            .foregroundStyle(.white, .white.opacity(0.82), .white.opacity(0.58))
            .tint(.white)
#else
        content
#endif
    }

    @ViewBuilder
    private func applyMacAssistantSecondaryTint<Content: View>(to content: Content) -> some View {
#if os(macOS)
        content
            .tint(.white.opacity(0.82))
#else
        content
#endif
    }

    private var searchPromptColor: Color {
#if os(macOS)
        .white.opacity(0.7)
#else
        Color.primary.opacity(0.58)
#endif
    }

    private var searchPrompt: Text {
        let prompt = Text(state.mode == .aiChat ? state.aiChatPreset.searchPlaceholder : String(localized: "Assistente"))
        return prompt.foregroundStyle(searchPromptColor)
    }

    var body: some View {
        controlsRow
            .padding(.vertical, 4)
            .padding(.horizontal, 20)
            .animation(.snappy(duration: 0.18, extraBounce: 0), value: state.isVisible)
            .onChange(of: isFocused) { _, newValue in
                if newValue && !state.isVisible {
                    state.isVisible = true
                }
            }
            .onChange(of: state.focusTrigger) { _, _ in
                isFocused = true
            }
            .onChange(of: state.defocusTrigger) { _, _ in
                isFocused = false
            }
    }

    private var controlsRow: some View {
        applyMacAssistantForegroundOverride(
            to: HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: state.mode == .aiChat ? "sparkles" : "sparkle.magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.secondary)

                    TextField(
                        "",
                        text: $state.searchText,
                        prompt: searchPrompt
                    )
                        .foregroundStyle(.primary)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .disableAutocorrection(true)
                        .focused($isFocused)
                        .submitLabel(isFocused && isEmpty && state.mode != .aiChat ? .done : (state.mode == .aiChat ? .send : .search))
                        .onSubmit {
                            let trimmed = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty {
                                state.dismiss()
                                return
                            }
                            if state.mode == .aiChat {
                                state.requestAIChatSend(trimmed, source: "UnifiedSearchBar.onSubmit")
                                state.searchText = ""
                            } else {
                                state.submitTrigger += 1
                            }
                        }

                    accessoryActions
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(height: chromeHeight)
                .background(searchBarBackground)
                .contentShape(Rectangle())
                .onTapGesture {
                    requestFocus()
                }
            }
        )
    }

    @ViewBuilder
    private var accessoryActions: some View {
        if hasTypedText {
            // Quando o usuário digita, mostramos apagar + enviar.
            inlineSendActions
        } else if state.mode == .aiChat {
            // Em SavorIA sem texto, oferecemos ditado para puxar a fala.
            DictationButton(targetText: $state.searchText)
        } else if shouldCollapseQuickActions {
            collapsedAccessoryMenu
        } else {
            expandedAccessoryActions
        }
    }

    private var inlineSendActions: some View {
        HStack(spacing: 4) {
            Button {
                state.searchText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Apagar"))

            Button {
                let trimmed = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if state.mode == .aiChat {
                    state.requestAIChatSend(trimmed, source: "UnifiedSearchBar.sendButton")
                    state.searchText = ""
                } else {
                    state.submitTrigger += 1
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Enviar"))
        }
    }

    private var collapsedAccessoryMenu: some View {
        applyMacAssistantSecondaryTint(
            to: Menu {
                listsQuickSection
                recipesQuickSection
                nutritionCollapsedQuickSection
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .menuOrder(.fixed)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        )
    }

    @ViewBuilder
    private var expandedAccessoryActions: some View {
        // Spacing 0 so the 40×40 hit areas sit flush — visually, the inner 16pt
        // icons keep ~24pt of breathing room from the surrounding chrome.
        HStack(spacing: 0) {
            quickMenuButton(icon: "list.bullet.clipboard") {
                listsQuickSection
            }
            quickMenuButton(icon: "book.closed") {
                recipesQuickSection
            }
            quickMenuButton(icon: "fork.knife") {
                nutritionQuickSection
            }
        }
    }

    private func quickMenuButton<MenuContent: View>(
        icon: String,
        @ViewBuilder content: () -> MenuContent
    ) -> some View {
        applyMacAssistantSecondaryTint(
            to: Menu {
                content()
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .menuOrder(.fixed)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        )
    }

    @ViewBuilder
    private var listsQuickSection: some View {
        Section("Listas") {
            Button("Procurar itens", systemImage: "magnifyingglass") {
                requestSearch(in: .lists)
            }
            Button("Criar item", systemImage: "square.and.pencil") {
                presentCommandAction(.addItem(prefill: "", iconFileName: nil, category: nil))
            }
        }
    }

    @ViewBuilder
    private var recipesQuickSection: some View {
        Section("Receitas") {
            Button("Procurar receitas", systemImage: "magnifyingglass") {
                requestSearch(in: .recipes)
            }
            Button("Criar receita", systemImage: "square.and.pencil") {
                presentCommandAction(.addRecipe(prefill: ""))
            }
        }
        Section("Importar receita") {
            Button("Colar link", systemImage: "link") {
                presentRecipeImport(.link)
            }
            Button("Importar da galeria", systemImage: "photo.on.rectangle.angled") {
                presentRecipeImport(.gallery)
            }
            Button("Ler com câmera", systemImage: "camera.viewfinder") {
                presentRecipeImport(.camera)
            }
            Button("Colar texto", systemImage: "text.alignleft") {
                presentRecipeImport(.text)
            }
            #if os(macOS)
            Button("Importar dos arquivos", systemImage: "folder.fill") {
                presentRecipeImport(.files)
            }
            #endif
        }
    }

    @ViewBuilder
    private var nutritionCollapsedQuickSection: some View {
        Section("Registros Salvos") {
            Button("Salvar alimento", systemImage: "fork.knife") {
                presentNutritionSheet(.manual())
            }
            Button("Alimentos salvos", systemImage: "clock.arrow.circlepath") {
                presentNutritionSheet(.recents)
            }
        }
        Section("Registros Manuais") {
            Button("Registrar manualmente", systemImage: "square.and.pencil") {
                presentNutritionSheet(.manual())
            }
        }
        Section("Registrar por…") {
            Button("Rótulo", systemImage: "doc.text.viewfinder") {
                presentNutritionSheet(.captureLabel)
            }
            Button("Galeria", systemImage: "photo") {
                presentFoodGalleryDirect()
            }
            #if os(iOS)
            Button("Câmera", systemImage: "camera") {
                presentFoodCameraDirect()
            }
            #endif
            Button("Voz", systemImage: "waveform") {
                presentNutritionSheet(.captureVoice)
            }
            Button("Texto", systemImage: "character.cursor.ibeam") {
                presentNutritionSheet(.captureText(prefillText: nil, autoAnalyze: false))
            }
        }
    }

    @ViewBuilder
    private var nutritionQuickSection: some View {
        Section("Registros Salvos") {
            Button("Salvar alimento", systemImage: "fork.knife") {
                presentNutritionSheet(.manual())
            }
            Button("Alimentos salvos", systemImage: "clock.arrow.circlepath") {
                presentNutritionSheet(.recents)
            }
        }
        Section("Registros Manuais") {
            Button("Registrar manualmente", systemImage: "square.and.pencil") {
                presentNutritionSheet(.manual())
            }
        }
        Section("Registrar por…") {
            Button("Rótulo", systemImage: "doc.text.viewfinder") {
                presentNutritionSheet(.captureLabel)
            }
            Button("Galeria", systemImage: "photo") {
                presentFoodGalleryDirect()
            }
            #if os(iOS)
            Button("Câmera", systemImage: "camera") {
                presentFoodCameraDirect()
            }
            #endif
            Button("Voz", systemImage: "waveform") {
                presentNutritionSheet(.captureVoice)
            }
            Button("Texto", systemImage: "character.cursor.ibeam") {
                presentNutritionSheet(.captureText(prefillText: nil, autoAnalyze: false))
            }
        }
    }

    @ViewBuilder
    private var searchBarBackground: some View {
        if #available(iOS 26, macOS 26, *) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        }
    }

    private func requestSearch(in context: SearchPageContext) {
        state.pageContext = context
        state.mode = .searching
        requestFocus()
    }

    private func presentCommandAction(_ action: CommandBarAction) {
        state.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onAction(action)
        }
    }

    private func presentRecipeImport(_ launchMode: RecipeImportLaunchMode) {
        state.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onOpenRecipeImport(launchMode)
        }
    }

    private func presentNutritionSheet(_ sheet: NutritionEntrySheet) {
        state.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            state.pendingNutritionSheet = sheet
        }
    }

    private func presentFoodCameraDirect() {
        state.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onOpenFoodCameraDirect()
        }
    }

    private func presentFoodGalleryDirect() {
        state.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onOpenFoodGalleryDirect()
        }
    }
}
