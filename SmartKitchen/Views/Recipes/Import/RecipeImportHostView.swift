import SwiftUI
import SwiftData
import PhotosUI

/// Host view that orchestrates the multi-step recipe import flow.
/// Presented from the Recipes toolbar or the Home action deck.
///
/// Flow:
///   picker → (link input | image picker | text input) → processing → preview → saved
@MainActor
struct RecipeImportHostView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Optional pre-filled source. When non-nil, skips the picker and starts immediately.
    let initialSource: RecipeImportSource?
    /// Callback invoked when a recipe is saved, with its ID.
    let onSaved: (UUID) -> Void

    @State private var coordinator = RecipeImportCoordinator()

    // Secondary sheets
    @State private var pickerInput: PickerInput? = nil
    @State private var selectedImage: PhotosPickerItem?
    @State private var showImagePicker = false

    private var importContainer: ModelContainer {
        CloudSyncService.shared.container
    }

    enum PickerInput: Identifiable {
        case link
        case text
        var id: String { String(describing: self) }
    }

    init(initialSource: RecipeImportSource? = nil, onSaved: @escaping (UUID) -> Void) {
        self.initialSource = initialSource
        self.onSaved = onSaved
    }

    var body: some View {
        Group {
            switch coordinator.phase {
            case .pickingSource:
                RecipeImportSourcePicker(
                    onPickLink: {
                        RecipeImportLogger.info("ui pick source=link")
                        pickerInput = .link
                    },
                    onPickImage: {
                        RecipeImportLogger.info("ui pick source=image")
                        showImagePicker = true
                    },
                    onPickVideo: {
                        // Em breve — Fase futura.
                        RecipeImportLogger.info("ui pick source=video (not implemented)")
                    },
                    onPickText: {
                        RecipeImportLogger.info("ui pick source=text")
                        pickerInput = .text
                    },
                    onCreateManual: {
                        RecipeImportLogger.info("ui action=create manual recipe")
                        dismiss()
                    }
                )

            case .processing(let stage):
                RecipeImportProcessingView(stage: stage) {
                    coordinator.cancel()
                }

            case .preview(let draft):
                NavigationStack {
                    RecipeImportPreviewView(
                        draft: draft,
                        onSave: { updatedDraft in
                            RecipeImportLogger.info("ui save tapped in preview")
                            let recipe = coordinator.save(draft: updatedDraft, in: modelContext)
                            onSaved(recipe.id)
                            dismiss()
                            return nil
                        },
                        onDiscard: {
                            RecipeImportLogger.info("ui discard tapped in preview")
                            coordinator.retry()
                        }
                    )
                }

            case .savedRecipeID:
                Color.clear
                    .onAppear { dismiss() }

            case .failed(let message):
                failureView(message: message)
            }
        }
        .modelContainer(importContainer)
        .sheet(item: $pickerInput) { input in
            switch input {
            case .link:
                RecipeLinkInputSheet { url in
                    RecipeImportLogger.info("ui link submitted url=\(url.absoluteString)")
                    pickerInput = nil
                    coordinator.start(.url(url))
                }
            case .text:
                RecipeTextInputSheet { text in
                    RecipeImportLogger.info("ui text submitted chars=\(text.count)")
                    pickerInput = nil
                    coordinator.start(.text(text))
                }
            }
        }
        .photosPicker(isPresented: $showImagePicker, selection: $selectedImage, matching: .images)
        .onChange(of: selectedImage) {
            loadSelectedImage()
        }
        .onAppear {
            RecipeImportLogger.info("import host appeared hasInitialSource=\(initialSource != nil)")
            if let source = initialSource, case .pickingSource = coordinator.phase {
                RecipeImportLogger.info("import host auto-starting initial source \(RecipeImportLogger.sourceSummary(source))")
                coordinator.start(source)
            }
        }
    }

    private func loadSelectedImage() {
        guard let item = selectedImage else { return }
        RecipeImportLogger.info("ui image selected from PhotosPicker")
        Task { @MainActor in
            if let data = try? await item.loadTransferable(type: Data.self) {
                RecipeImportLogger.info("ui image loaded bytes=\(data.count)")
                coordinator.start(.image(data))
            } else {
                RecipeImportLogger.error("ui failed to load selected image")
            }
        }
    }

    // MARK: - Failure

    private func failureView(message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Não consegui importar")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            HStack(spacing: 12) {
                Button("Cancelar", role: .cancel) {
                    dismiss()
                }
                Button("Tentar outra") {
                    coordinator.retry()
                }
                .buttonStyle(.borderedProminent)
                .tint(PageTheme.recipes.accentColor)
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Input sheets

private struct RecipeLinkInputSheet: View {
    let onSubmit: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://...", text: $text, axis: .vertical)
                        .textContentType(.URL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled(true)
                        .focused($focused)
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Link da receita")
                } footer: {
                    Text("Cole o link de qualquer site, blog ou rede social. Vamos extrair o que der.")
                }

                Button {
                    if let pasted = pasteboardURLString() {
                        text = pasted
                    }
                } label: {
                    Label("Colar do clipboard", systemImage: "doc.on.clipboard")
                }
            }
            .navigationTitle("Colar link")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importar") { submit() }
                        .font(.body.weight(.semibold))
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    focused = true
                }
            }
        }
    }

    private func submit() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: raw), components.scheme != nil, components.host != nil else {
            // Try adding https prefix
            if let url = URL(string: "https://\(raw)"), url.host != nil {
                onSubmit(url)
                return
            }
            errorMessage = "URL inválida."
            return
        }
        if components.scheme == nil { components.scheme = "https" }
        guard let url = components.url else {
            errorMessage = "URL inválida."
            return
        }
        onSubmit(url)
    }

    private func pasteboardURLString() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #else
        return NSPasteboard.general.string(forType: .string)
        #endif
    }
}

private struct RecipeTextInputSheet: View {
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Cole aqui o texto da receita...", text: $text, axis: .vertical)
                        .lineLimit(6...20)
                        .focused($focused)
                } header: {
                    Text("Texto da receita")
                } footer: {
                    Text("Pode ser bagunçado. Nossa IA organiza em ingredientes e passos.")
                }

                Button {
                    if let pasted = pasteboardString() {
                        text = pasted
                    }
                } label: {
                    Label("Colar do clipboard", systemImage: "doc.on.clipboard")
                }
            }
            .navigationTitle("Colar texto")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importar") {
                        onSubmit(text)
                    }
                    .font(.body.weight(.semibold))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    focused = true
                }
            }
        }
    }

    private func pasteboardString() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #else
        return NSPasteboard.general.string(forType: .string)
        #endif
    }
}
