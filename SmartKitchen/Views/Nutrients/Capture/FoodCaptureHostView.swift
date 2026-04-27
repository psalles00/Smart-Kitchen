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
    @State private var preferredDetent: PresentationDetent
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
        #if os(iOS)
        _preferredDetent = State(initialValue: preloadedImage != nil ? .large : .medium)
        #endif
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
        .presentationDetents([.medium, .large], selection: $preferredDetent)
        .presentationDragIndicator(.visible)
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
        .modalNavigationTitle(captureModalTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
        }
    }

    private var photoGathering: some View {
        ScrollView {
            VStack(spacing: 18) {
                capturePanel {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(PageTheme.nutrients.accentColor.opacity(0.12))
                                .frame(width: 56, height: 56)

                            Image(systemName: mode == .photo ? "camera.macro" : "doc.text.viewfinder")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(PageTheme.nutrients.gradient)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode == .photo ? "Registrar por foto" : "Registrar por rótulo")
                                .font(.title3.weight(.semibold))
                            Text(mode == .photo ? "IA visual" : "Leitura assistida")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PageTheme.nutrients.accentColor)
                        }

                        Spacer()
                    }

                    Text(mode == .photo
                         ? "Tire uma foto do prato ou escolha uma imagem já salva para estimar calorias e macros automaticamente."
                         : "Fotografe o rótulo nutricional ou use uma imagem da galeria para extrair os valores da embalagem.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                capturePanel {
                    #if os(iOS)
                    Button {
                        showCamera = true
                    } label: {
                        Label(mode == .photo ? "Abrir câmera" : "Fotografar agora", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PageTheme.nutrients.accentColor)
                    .controlSize(.large)
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
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .modalNavigationTitle(captureModalTitle)
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
        ScrollView {
            VStack(spacing: 14) {
                compactCapturePanel {
                    HStack(alignment: .top, spacing: 12) {
                        captureBadge(systemImage: "square.and.pencil")

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Texto livre")
                                .font(.headline)
                            Text("Ingredientes, quantidades e preparo em uma frase curta.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        captureCounterBadge(typedText.count)
                    }

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.05))

                        TextEditor(text: $typedText)
                            .frame(minHeight: 112, maxHeight: 112)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            #if os(iOS)
                            .scrollContentBackground(.hidden)
                            #endif

                        if typedText.isEmpty {
                            Text("Ex.: 2 ovos mexidos, pão integral e meia banana.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            stickyAnalyzeBar(
                isDisabled: typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: startTextAnalysis
            )
        }
        .modalNavigationTitle("Registrar por texto")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var voiceGathering: some View {
        #if os(iOS)
        ScrollView {
            VStack(spacing: 14) {
                compactCapturePanel {
                    HStack(alignment: .top, spacing: 12) {
                        captureBadge(
                            systemImage: speech.state == .recording ? "waveform.circle.fill" : "waveform",
                            tint: speech.state == .recording ? .red : PageTheme.nutrients.accentColor
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(speech.state == .recording ? "Ouvindo agora" : "Ditado")
                                .font(.headline)
                            Text(speech.state == .recording ? "Fale normalmente. A transcrição aparece em tempo real." : "Revise a transcrição antes de analisar.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        captureCounterBadge(speech.transcript.count)
                    }

                    HStack(spacing: 10) {
                        Button {
                            toggleVoiceCapture()
                        } label: {
                            Label(
                                speech.state == .recording ? "Parar" : (speech.transcript.isEmpty ? "Ditar" : "Gravar de novo"),
                                systemImage: speech.state == .recording ? "stop.circle.fill" : "mic.fill"
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(speech.state == .recording ? .red : PageTheme.nutrients.accentColor)

                        if !speech.transcript.isEmpty {
                            Button {
                                speech.reset()
                                typedText = ""
                            } label: {
                                Label("Limpar", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                        }

                        Spacer(minLength: 0)
                    }

                    Text(speech.transcript.isEmpty ? "Fale o que você comeu. Ex.: arroz, feijão e frango grelhado." : speech.transcript)
                        .font(.body)
                        .foregroundStyle(speech.transcript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                }

                if case .error(let message) = speech.state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            stickyAnalyzeBar(
                isDisabled: speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: analyzeVoiceTranscript
            )
        }
        .modalNavigationTitle("Registrar por voz")
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
                Button("Voltar") { setStage(.gathering) }
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

    private var captureModalTitle: String {
        switch mode {
        case .photo:          "Registrar por foto"
        case .nutritionLabel: "Registrar por rótulo"
        case .text:           "Registrar por texto"
        case .voice:          "Registrar por voz"
        }
    }

    @ViewBuilder
    private func capturePanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PageTheme.nutrients.accentColor.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func compactCapturePanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func captureBadge(systemImage: String, tint: Color = PageTheme.nutrients.accentColor) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(tint.opacity(0.12))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
    }

    private func captureCounterBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private func stickyAnalyzeBar(isDisabled: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: action) {
                Label("Analisar", systemImage: "sparkles")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        isDisabled
                            ? PageTheme.nutrients.accentColor.opacity(0.35)
                            : PageTheme.nutrients.accentColor,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func setStage(_ newStage: Stage, animated: Bool = true) {
        #if os(iOS)
        let targetDetent: PresentationDetent
        switch newStage {
        case .gathering:
            targetDetent = .medium
        case .analyzing, .result, .error:
            targetDetent = .large
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.22)) {
                preferredDetent = targetDetent
            }
        } else {
            preferredDetent = targetDetent
        }
        #endif

        stage = newStage
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = PlatformImage(data: data) {
                capturedImage = img
                startImageAnalysis()
            }
        } catch {
            await MainActor.run { setStage(.error(error.localizedDescription)) }
        }
    }

    private func startImageAnalysis() {
        guard let image = capturedImage else { return }
        setStage(.analyzing)
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
                    await MainActor.run { setStage(.result(analysis)) }
                case .nutritionLabel:
                    let label = try await ai.analyzeNutritionLabel(imageData: data)
                    let serving = label.servingSizeGrams ?? 100
                    let analysis = label.scaled(to: serving)
                    await MainActor.run { setStage(.result(analysis)) }
                case .text, .voice:
                    break
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { setStage(.error(msg)) }
            }
        }
    }

    private func startTextAnalysis() {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        setStage(.analyzing)
        Task {
            do {
                let analysis = try await ai.analyzeText(description: text)
                await MainActor.run { setStage(.result(analysis)) }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { setStage(.error(msg)) }
            }
        }
    }

    #if os(iOS)
    private func toggleVoiceCapture() {
        if speech.state == .recording {
            speech.stop()
        } else {
            if !speech.transcript.isEmpty {
                speech.reset()
            }
            speech.start()
        }
    }

    private func analyzeVoiceTranscript() {
        if speech.state == .recording {
            speech.stop()
        }
        let text = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typedText = text
        startTextAnalysis()
    }
    #endif

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
