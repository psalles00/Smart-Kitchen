import SwiftUI
import PhotosUI

/// Host único para os 4 modos de captura automática: foto, rótulo, voz e texto.
/// Gerencia ciclo gathering → analyzing → result → (erro).
struct FoodCaptureHostView: View {
    enum InitialInput {
        case chooser
        case camera
        case gallery
    }

    enum Mode {
        case photo
        case nutritionLabel
        case text
        case voice
    }

    enum Stage {
        case gathering
        case analyzing
        case result(FoodAnalysis)
        case error(String)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let logDate: Date
    let initialInput: InitialInput
    let preloadedImage: PlatformImage?

    @State private var stage: Stage
    @State private var capturedImage: PlatformImage?
    @State private var typedText: String = ""
    @State private var showCamera: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var hasTriggeredInitialInput = false
    @State private var hasTriggeredPreloadedAnalysis = false

    #if os(iOS)
    @State private var speech = NutritionSpeechRecognizer()
    #endif

    private let ai = NutritionAIService()

    init(mode: Mode,
         logDate: Date,
         initialInput: InitialInput = .chooser,
         preloadedImage: PlatformImage? = nil) {
        self.mode = mode
        self.logDate = logDate
        self.initialInput = initialInput
        self.preloadedImage = preloadedImage
        // Start directly in analyzing stage when a preloaded image is provided,
        // so no gathering UI is ever rendered.
        if preloadedImage != nil {
            _stage = State(initialValue: .analyzing)
            _capturedImage = State(initialValue: preloadedImage)
        } else {
            _stage = State(initialValue: .gathering)
        }
    }

    private var isDirectPhotoShortcut: Bool {
        mode == .photo && initialInput != .chooser
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .gathering:
                    gatheringView
                case .analyzing:
                    FoodAnalyzingView(image: capturedImage, message: analyzingMessage)
                case .result(let analysis):
                    FoodResultView(analysis: analysis, image: capturedImage, logDate: logDate)
                case .error(let message):
                    errorView(message)
                }
            }
            .tint(PageTheme.nutrients.accentColor)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            FoodCameraPicker { image in
                capturedImage = image
                startImageAnalysis()
            }
            .ignoresSafeArea()
        }
        #endif
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, new in
            guard let new else { return }
            Task { await loadPhoto(new) }
        }
        .onChange(of: showCamera) { _, isPresented in
            guard !isPresented, isDirectPhotoShortcut else { return }
            DispatchQueue.main.async {
                guard capturedImage == nil, case .gathering = stage else { return }
                dismiss()
            }
        }
        .onChange(of: showPhotoPicker) { _, isPresented in
            guard !isPresented, isDirectPhotoShortcut else { return }
            DispatchQueue.main.async {
                guard selectedPhotoItem == nil, capturedImage == nil, case .gathering = stage else { return }
                dismiss()
            }
        }
        .onAppear {
            triggerInitialInputIfNeeded()
            triggerPreloadedAnalysisIfNeeded()
        }
    }

    // MARK: - Gathering UI by mode

    @ViewBuilder
    private var gatheringView: some View {
        switch mode {
        case .photo:
            if initialInput == .chooser {
                photoGathering
            } else {
                directLaunchPlaceholder
            }
        case .nutritionLabel:
            photoGathering
        case .text:
            textGathering
        case .voice:
            voiceGathering
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
        }
    }

    private var photoGathering: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: mode == .photo ? "camera.fill" : "barcode.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(PageTheme.nutrients.gradient)
            Text(mode == .photo ? "Foto da refeição" : "Rótulo nutricional")
                .font(.sectionTitle)
            Text(mode == .photo
                 ? "Tire uma foto do prato para a IA identificar e estimar os macros automaticamente."
                 : "Fotografe o rótulo nutricional de uma embalagem para extrair os valores por 100 g.")
                .font(.serifBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            #if os(iOS)
            Button {
                showCamera = true
            } label: {
                Label("Usar câmera", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(PageTheme.nutrients.accentColor)
            .controlSize(.large)
            .padding(.horizontal, 32)
            #endif

            Button {
                showPhotoPicker = true
            } label: {
                Label("Escolher da galeria", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(PageTheme.nutrients.accentColor)
            .controlSize(.large)
            .padding(.horizontal, 32)

            Spacer()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
        }
    }

    private func triggerInitialInputIfNeeded() {
        guard !hasTriggeredInitialInput else { return }
        guard case .gathering = stage else { return }
        guard mode == .photo else { return }

        hasTriggeredInitialInput = true

        switch initialInput {
        case .chooser:
            break
        case .camera:
            #if os(iOS)
            showCamera = true
            #endif
        case .gallery:
            showPhotoPicker = true
        }
    }

    private func triggerPreloadedAnalysisIfNeeded() {
        guard !hasTriggeredPreloadedAnalysis else { return }
        guard preloadedImage != nil else { return }
        hasTriggeredPreloadedAnalysis = true
        startImageAnalysis()
    }

    private var textGathering: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Descreva a refeição")
                    .font(.headline)
                Text("Ex.: \"2 ovos mexidos, uma fatia de pão integral e meia banana\".")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextEditor(text: $typedText)
                .frame(minHeight: 160)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if typedText.isEmpty {
                        Text("Descrição…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                startTextAnalysis()
            } label: {
                Label("Analisar", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(PageTheme.nutrients.accentColor)
            .controlSize(.large)
            .disabled(typedText.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer()
        }
        .padding(20)
        .modalNavigationTitle("Descrição por texto")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var voiceGathering: some View {
        #if os(iOS)
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(speech.state == .recording ? .red : PageTheme.nutrients.accentColor)
                .padding(24)
                .background(
                    Circle().fill(
                        (speech.state == .recording ? Color.red : PageTheme.nutrients.accentColor)
                            .opacity(0.12)
                    )
                )
                .scaleEffect(speech.state == .recording ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.4), value: speech.state)

            Text(speech.transcript.isEmpty ? "Fale o que você comeu…" : speech.transcript)
                .font(.body)
                .foregroundStyle(speech.transcript.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(minHeight: 80)

            if case .error(let message) = speech.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 12) {
                Button {
                    // Para a gravação (se ainda estiver ativa) e dispara a
                    // análise com a transcrição capturada até o momento.
                    if speech.state == .recording {
                        speech.stop()
                    }
                    let text = speech.transcript.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { return }
                    typedText = text
                    startTextAnalysis()
                } label: {
                    Label("Analisar", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(PageTheme.nutrients.accentColor)
                .controlSize(.large)
                .disabled(speech.transcript.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .modalNavigationTitle("Por voz")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { speech.stop(); dismiss() }
            }
        }
        .onAppear { speech.start() }
        .onDisappear { speech.stop() }
        #else
        Text("Voz disponível apenas no iOS.")
            .foregroundStyle(.secondary)
        #endif
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Não consegui analisar")
                .font(.sectionTitle)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 10) {
                Button("Voltar") { stage = .gathering }
                    .buttonStyle(.bordered)
                Button("Fechar") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(PageTheme.nutrients.accentColor)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var analyzingMessage: String {
        switch mode {
        case .photo:           "Identificando a refeição…"
        case .nutritionLabel:  "Lendo rótulo nutricional…"
        case .text:            "Estimando nutrientes…"
        case .voice:           "Estimando nutrientes…"
        }
    }

    // MARK: - Actions

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = PlatformImage(data: data) {
                capturedImage = img
                startImageAnalysis()
            }
        } catch {
            await MainActor.run { stage = .error(error.localizedDescription) }
        }
    }

    private func startImageAnalysis() {
        guard let image = capturedImage else { return }
        stage = .analyzing
        Task {
            do {
                // Normaliza para ≤1024px JPEG 0.8
                #if canImport(UIKit)
                let resized = resize(image, maxDim: 1024)
                guard let data = resized.jpegData(compressionQuality: 0.8) else {
                    throw NutritionAIService.NutritionAIError.emptyResponse
                }
                #else
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
                else { throw NutritionAIService.NutritionAIError.emptyResponse }
                #endif

                switch mode {
                case .photo:
                    let analysis = try await ai.analyzeFoodImage(imageData: data)
                    await MainActor.run { stage = .result(analysis) }
                case .nutritionLabel:
                    let label = try await ai.analyzeNutritionLabel(imageData: data)
                    let serving = label.servingSizeGrams ?? 100
                    let analysis = label.scaled(to: serving)
                    await MainActor.run { stage = .result(analysis) }
                case .text, .voice:
                    break
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { stage = .error(msg) }
            }
        }
    }

    private func startTextAnalysis() {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stage = .analyzing
        Task {
            do {
                let analysis = try await ai.analyzeText(description: text)
                await MainActor.run { stage = .result(analysis) }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { stage = .error(msg) }
            }
        }
    }

    // MARK: - Image resize

    #if canImport(UIKit)
    private func resize(_ image: UIImage, maxDim: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxDim / max(size.width, size.height), 1)
        if scale >= 1 { return image }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
    #endif
}
