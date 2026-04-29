#if os(iOS)
import SwiftUI

/// Botão inline de ditado usado na barra unificada do Modo IA.
///
/// Inicia/para a captura de voz via `NutritionSpeechRecognizer` e escreve a
/// transcrição diretamente no `targetText` (a mesma `searchText` da barra).
/// Não abre tela nova nem usa o teclado de ditado do sistema.
struct DictationButton: View {
    @Binding var targetText: String

    @State private var recognizer = NutritionSpeechRecognizer()
    @State private var baselineText: String = ""
    @State private var isRecording: Bool = false
    @State private var pulseTrigger: Bool = false
    @State private var showError: Bool = false
    @State private var errorText: String = ""

    var body: some View {
        Button {
            toggle()
        } label: {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.18))
                        .frame(width: 30, height: 30)
                        .scaleEffect(pulseTrigger ? 1.18 : 1.0)
                        .opacity(pulseTrigger ? 0.0 : 0.85)
                        .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: false), value: pulseTrigger)
                }
                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isRecording ? Color.red : Color.secondary)
            }
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: recognizer.transcript) { _, newValue in
            guard isRecording else { return }
            // Append live transcript to baseline (preserva texto digitado antes
            // do usuário tocar no microfone).
            if baselineText.isEmpty {
                targetText = newValue
            } else if newValue.isEmpty {
                targetText = baselineText
            } else {
                targetText = baselineText + " " + newValue
            }
        }
        .onChange(of: recognizer.state) { _, state in
            switch state {
            case .recording:
                isRecording = true
                pulseTrigger = true
            case .finished, .idle:
                isRecording = false
                pulseTrigger = false
            case .error(let message):
                isRecording = false
                pulseTrigger = false
                errorText = message
                showError = true
            }
        }
        .alert("Não foi possível usar o microfone", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText)
        }
    }

    private func toggle() {
        if isRecording {
            recognizer.stop()
        } else {
            baselineText = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            recognizer.reset()
            // Reseta o transcript exibido em targetText após o reset.
            if !baselineText.isEmpty {
                targetText = baselineText
            } else {
                targetText = ""
            }
            recognizer.start()
        }
    }
}
#endif
