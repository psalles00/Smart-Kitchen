import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

enum RecipeImportLaunchMode: Equatable {
    case picker
    case link
    case text
    case gallery
    case camera
    case files
}

/// Host view that orchestrates the multi-step recipe import flow.
/// Presented from recipe entry points such as the Recipes toolbar or assistant shortcuts.
///
/// Flow:
///   picker/direct entry → (link input | image picker | file picker | camera | text input) → processing → preview → saved
@MainActor
struct RecipeImportHostView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Optional pre-filled source. When non-nil, skips the picker and starts immediately.
    let initialSource: RecipeImportSource?
    let launchMode: RecipeImportLaunchMode
    /// Callback invoked when a recipe is saved, with its ID.
    let onSaved: (UUID) -> Void

    @State private var coordinator = RecipeImportCoordinator()

    // Secondary sheets
    @State private var pickerInput: PickerInput? = nil
    @State private var selectedImage: PhotosPickerItem?
    @State private var showImagePicker = false
    @State private var showCameraPicker = false
    @State private var showCameraUnavailableAlert = false
    @State private var showFileImporter = false
    @State private var hasTriggeredInitialLaunch = false

    private var importContainer: ModelContainer {
        CloudSyncService.shared.container
    }

    enum PickerInput: Identifiable {
        case link
        case text
        var id: String { String(describing: self) }
    }

    init(
        initialSource: RecipeImportSource? = nil,
        launchMode: RecipeImportLaunchMode = .picker,
        onSaved: @escaping (UUID) -> Void
    ) {
        self.initialSource = initialSource
        self.launchMode = launchMode
        self.onSaved = onSaved
        RecipeImportLogger.info("import host init hasInitialSource=\(initialSource != nil) launchMode=\(launchMode)")
    }

    private var isDirectLaunchShortcut: Bool {
        initialSource == nil && launchMode != .picker
    }

    var body: some View {
        Group {
            switch coordinator.phase {
            case .pickingSource:
                if isDirectLaunchShortcut {
                    directLaunchPlaceholder
                } else {
                    RecipeImportSourcePicker(
                        onPickLink: {
                            RecipeImportLogger.info("ui pick source=link")
                            pickerInput = .link
                        },
                        onPickImage: {
                            RecipeImportLogger.info("ui pick source=image")
                            launchGalleryPicker()
                        },
                        onPickCamera: {
                            RecipeImportLogger.info("ui pick source=camera")
                            launchCameraPicker()
                        },
                        onPickFiles: {
                            RecipeImportLogger.info("ui pick source=file")
                            launchFileImporter()
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
                }

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

            case .failed(let message):
                failureView(message: message)
            }
        }
        .modelContainer(importContainer)
        .sheet(item: $pickerInput, onDismiss: handleDirectShortcutDismiss) { input in
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
        .sheet(isPresented: $showCameraPicker) {
            cameraImportSheet
        }
        .photosPicker(isPresented: $showImagePicker, selection: $selectedImage, matching: .images)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
            loadImportedFile(result)
        }
        .alert("Câmera indisponível", isPresented: $showCameraUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Não foi possível acessar a câmera neste dispositivo agora.")
        }
        .onChange(of: showImagePicker) { _, isPresented in
            guard !isPresented else { return }
            DispatchQueue.main.async {
                handleDirectShortcutDismiss()
            }
        }
        .onChange(of: showCameraPicker) { _, isPresented in
            guard !isPresented else { return }
            DispatchQueue.main.async {
                handleDirectShortcutDismiss()
            }
        }
        .onChange(of: showFileImporter) { _, isPresented in
            guard !isPresented else { return }
            DispatchQueue.main.async {
                handleDirectShortcutDismiss()
            }
        }
        .onChange(of: selectedImage) {
            loadSelectedImage()
        }
        .onAppear {
            RecipeImportLogger.info("import host appeared hasInitialSource=\(initialSource != nil) phase=\(phaseDescription(coordinator.phase))")
            if let source = initialSource, case .pickingSource = coordinator.phase {
                RecipeImportLogger.info("import host auto-starting initial source \(RecipeImportLogger.sourceSummary(source))")
                coordinator.start(source)
                return
            }

            triggerInitialLaunchIfNeeded()
        }
        .onDisappear {
            RecipeImportLogger.info("import host disappeared phase=\(phaseDescription(coordinator.phase))")
        }
    }

    private func phaseDescription(_ phase: RecipeImportCoordinator.Phase) -> String {
        switch phase {
        case .pickingSource: return "pickingSource"
        case .processing(let stage): return "processing(\(stage.title))"
        case .preview: return "preview"
        case .savedRecipeID: return "savedRecipeID"
        case .failed(let msg): return "failed(\(msg))"
        }
    }

    private var directLaunchPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Abrindo…")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func handleDirectShortcutDismiss() {
        guard isDirectLaunchShortcut else { return }
        guard case .pickingSource = coordinator.phase else { return }
        guard pickerInput == nil,
              !showImagePicker,
              !showCameraPicker,
              !showFileImporter
        else { return }

        dismiss()
    }

    private func loadSelectedImage() {
        guard let item = selectedImage else { return }
        selectedImage = nil
        RecipeImportLogger.info("ui image selected from PhotosPicker")
        Task { @MainActor in
            if let data = try? await item.loadTransferable(type: Data.self) {
                RecipeImportLogger.info("ui image loaded bytes=\(data.count)")
                coordinator.start(.image(data))
            } else {
                RecipeImportLogger.error("ui failed to load selected image")
                coordinator.phase = .failed(message: "Não foi possível abrir a imagem selecionada.")
            }
        }
    }

    private func triggerInitialLaunchIfNeeded() {
        guard !hasTriggeredInitialLaunch else { return }
        hasTriggeredInitialLaunch = true

        switch launchMode {
        case .picker:
            break
        case .link:
            pickerInput = .link
        case .text:
            pickerInput = .text
        case .gallery:
            launchGalleryPicker()
        case .camera:
            launchCameraPicker()
        case .files:
            launchFileImporter()
        }
    }

    private func launchGalleryPicker() {
        selectedImage = nil
        showImagePicker = true
    }

    private func launchCameraPicker() {
        #if os(iOS)
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showCameraUnavailableAlert = true
            return
        }
        #endif

        showCameraPicker = true
    }

    private func launchFileImporter() {
        #if os(macOS)
        showFileImporter = true
        #endif
    }

    private func loadImportedFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if scopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                RecipeImportLogger.info("ui file loaded bytes=\(data.count)")
                coordinator.start(.image(data))
            } catch {
                RecipeImportLogger.error("ui failed to load file error=\(error.localizedDescription)")
                coordinator.phase = .failed(message: "Não foi possível abrir o arquivo selecionado.")
            }

        case .failure(let error):
            RecipeImportLogger.info("ui file picker closed error=\(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private var cameraImportSheet: some View {
        #if os(iOS)
        CameraMediaPicker(mode: .photoOnly) { media in
            RecipeImportLogger.info("ui camera captured bytes=\(media.data.count)")
            coordinator.start(.image(media.data))
        }
        #else
        MacCameraMediaPicker(mode: .photoOnly) { media in
            RecipeImportLogger.info("ui camera captured bytes=\(media.data.count)")
            coordinator.start(.image(media.data))
        }
        #endif
    }

    // MARK: - Failure

    private func failureView(message: String) -> some View {
        let canDeepRetry = coordinator.supportsDeepAttempt && !coordinator.deepAttemptUsed
        return VStack(spacing: 18) {
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

            VStack(spacing: 12) {
                if canDeepRetry {
                    Button {
                        RecipeImportLogger.info("ui deep retry tapped from failure view")
                        coordinator.runDeepAttempt()
                    } label: {
                        HStack {
                            Image(systemName: coordinator.isDeepAttempting ? "wand.and.stars.inverse" : "wand.and.stars")
                            Text(coordinator.isDeepAttempting ? "Tentando mais profundamente..." : "Tentar mais profundamente")
                        }
                        .frame(maxWidth: .infinity)
                        .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(PageTheme.recipes.accentColor)
                    .disabled(coordinator.isDeepAttempting || coordinator.deepAttemptUsed)
                }

                HStack(spacing: 12) {
                    Button("Cancelar", role: .cancel) {
                        dismiss()
                    }
                    .disabled(coordinator.isDeepAttempting)

                    if !canDeepRetry {
                        Button("Tentar outra") {
                            RecipeImportLogger.info("ui retry tapped from failure view")
                            coordinator.retry()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PageTheme.recipes.accentColor)
                        .disabled(coordinator.isDeepAttempting)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Input sheets

struct RecipeLinkInputSheet: View {
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
            .modalNavigationTitle("Colar link")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importar") { submit() }
                        .font(.body.weight(.semibold))
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                #else
                ToolbarItem {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem {
                    Button("Importar") { submit() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                #endif
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

struct RecipeTextInputSheet: View {
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
            .modalNavigationTitle("Colar texto")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
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
                #else
                ToolbarItem {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem {
                    Button("Importar") {
                        onSubmit(text)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                #endif
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
