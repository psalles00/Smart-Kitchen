#if os(iOS)
import Foundation
import AVFoundation
import Speech

/// Wrapper de SFSpeechRecognizer com streaming de transcrições parciais.
///
/// Os callbacks de `SFSpeechRecognizer.requestAuthorization`,
/// `AVAudioApplication.requestRecordPermission` e `recognitionTask(with:)` são
/// entregues em queues arbitrárias do TCC/Speech. Em Swift 6, closures literais
/// dentro de uma classe `@MainActor` herdam esse isolamento, e o runtime aborta
/// com `_swift_task_checkIsolatedSwift` quando o callback é invocado fora do main.
/// Por isso, esses callbacks são embrulhados em helpers `nonisolated static`.
@Observable
@MainActor
final class NutritionSpeechRecognizer {
    enum State: Equatable {
        case idle
        case recording
        case finished
        case error(String)
    }

    private(set) var transcript: String = ""
    private(set) var state: State = .idle

    @ObservationIgnored private let recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var isStarting: Bool = false

    init(locale: Locale = AppLocalization.current().speechRecognizerLocale) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: AppLocalization.current().fallbackSpeechRecognizerLocale)
    }

    // MARK: - Public

    /// Idempotente. Inicia (ou ignora) o ciclo de gravação.
    func start() {
        guard state != .recording, !isStarting else { return }
        isStarting = true

        Task { [weak self] in
            let speechAuth = await Self.requestSpeechAuthorization()
            guard let self else { return }
            guard speechAuth == .authorized else {
                self.isStarting = false
                self.state = .error(String(localized: "Permissão de reconhecimento de voz negada. Habilite em Ajustes."))
                return
            }

            let micAllowed = await Self.requestMicrophonePermission()
            guard !Task.isCancelled else { return }
            guard micAllowed else {
                self.isStarting = false
                self.state = .error(String(localized: "Permissão de microfone negada. Habilite em Ajustes."))
                return
            }

            self.isStarting = false
            guard self.state != .recording else { return }
            self.beginSession()
        }
    }

    func stop() {
        guard state == .recording else { return }
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        state = .finished
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func reset() {
        stop()
        transcript = ""
        state = .idle
    }

    // MARK: - Permission helpers (nonisolated)

    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }

    private nonisolated static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { allowed in
                cont.resume(returning: allowed)
            }
        }
    }

    // MARK: - Session

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            state = .error(String(localized: "Reconhecimento de voz indisponível neste dispositivo."))
            return
        }
        task?.cancel()
        task = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .error(String(localized: "Falha ao configurar áudio."))
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        request = req

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            request = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            state = .error(String(localized: "Entrada de áudio indisponível. Verifique o microfone do dispositivo."))
            return
        }
        // O bloco do tap é executado na thread real-time de áudio. Encaminhamos
        // a instalação por um helper nonisolated para o closure literal não
        // herdar `@MainActor` (que dispararia _swift_task_checkIsolatedSwift).
        Self.installAudioTap(on: input, format: format, request: req)
        engine.prepare()
        do {
            try engine.start()
            state = .recording
        } catch {
            input.removeTap(onBus: 0)
            request = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            state = .error(String(localized: "Falha ao iniciar gravação."))
            return
        }

        // recognitionTask: closure entregue fora do MainActor, então
        // encaminhamos via helper nonisolated.
        self.task = Self.makeRecognitionTask(
            recognizer: recognizer,
            request: req
        ) { [weak self] transcript, isFinal, hasError in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let transcript {
                    self.transcript = transcript
                }
                if hasError || isFinal {
                    self.stop()
                }
            }
        }
    }

    private nonisolated static func makeRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        update: @Sendable @escaping (_ transcript: String?, _ isFinal: Bool, _ hasError: Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            update(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    private nonisolated static func installAudioTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }
}
#endif
