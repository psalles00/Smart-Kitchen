#if os(iOS)
import Foundation
import AVFoundation
import Speech

/// Wrapper simples de SFSpeechRecognizer com streaming de transcrições parciais.
@MainActor
@Observable
final class NutritionSpeechRecognizer {
    enum State: Equatable {
        case idle
        case recording
        case finished
        case error(String)
    }

    private(set) var transcript: String = ""
    private(set) var state: State = .idle

    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    init(locale: Locale = Locale(identifier: "pt-BR")) {
        self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Public

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard let self else { return }
                guard auth == .authorized else {
                    self.state = .error("Permissão de reconhecimento de voz negada. Habilite em Ajustes.")
                    return
                }
                AVAudioApplication.requestRecordPermission { allowed in
                    DispatchQueue.main.async {
                        guard allowed else {
                            self.state = .error("Permissão de microfone negada. Habilite em Ajustes.")
                            return
                        }
                        self.beginSession()
                    }
                }
            }
        }
    }

    func stop() {
        guard state == .recording else { return }
        engine.stop()
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

    // MARK: - Internals

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            state = .error("Reconhecimento de voz indisponível neste dispositivo.")
            return
        }
        task?.cancel()
        task = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .error("Falha ao configurar áudio.")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        request = req

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
            state = .recording
        } catch {
            state = .error("Falha ao iniciar gravação.")
            return
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stop()
                }
            }
        }
    }
}
#endif
