import SwiftUI
#if os(iOS)
import Speech
#endif

// MARK: - Unified Search Bar

/// Liquid Glass search bar displayed in the shader area.
/// Uses `.glassEffect()` on iOS 26+, falls back to `.ultraThinMaterial`.
struct UnifiedSearchBar: View {
    @ObservedObject var state: SearchBarState
    let onSubmit: (String) -> Void

    @FocusState private var isFocused: Bool
    @State private var showDictation = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.mode == .aiChat ? "paperplane.fill" : "sparkle.magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(state.mode == .aiChat ? "Converse com a IA…" : "Adicione, busque, ou pergunte…", text: $state.searchText)
                .foregroundStyle(.primary)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .disableAutocorrection(true)
                .focused($isFocused)
                .submitLabel(state.mode == .aiChat ? .send : .search)
                .onSubmit {
                    let trimmed = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    if state.mode == .aiChat {
                        state.pendingChatMessage = trimmed
                        state.searchText = ""
                    } else {
                        state.submitTrigger += 1
                    }
                }

            if !state.searchText.isEmpty {
                Button {
                    state.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            // Dictation button
            #if os(iOS)
            Button {
                startDictation()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            #endif

            // Attachment menu (gallery + camera)
            attachmentMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(searchBarBackground)
        .padding(.horizontal, 20)
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

    // MARK: - Background

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

    // MARK: - Attachment Menu

    private var attachmentMenu: some View {
        Menu {
            Button {
                // Placeholder: photo picker
            } label: {
                Label("Inserir da Galeria", systemImage: "photo.on.rectangle")
            }

            Button {
                // Placeholder: camera capture
            } label: {
                Label("Tirar Foto", systemImage: "camera")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dictation

    #if os(iOS)
    private func startDictation() {
        // Trigger the system keyboard dictation by requesting speech authorization
        // and switching the keyboard to dictation mode via first responder
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                if status == .authorized {
                    // Focus the text field — iOS will show microphone on keyboard
                    isFocused = true
                    // Use UITextInput to toggle dictation if available
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = scene.windows.first,
                       let responder = window.findFirstResponder() {
                        // The keyboard dictation button becomes available when focused
                        // We trigger it by setting input mode
                        responder.perform(NSSelectorFromString("toggleDictation:"), with: nil)
                    }
                }
            }
        }
    }
    #endif
}

// MARK: - First Responder Helper

#if os(iOS)
private extension UIView {
    func findFirstResponder() -> UIView? {
        if isFirstResponder { return self }
        for subview in subviews {
            if let responder = subview.findFirstResponder() {
                return responder
            }
        }
        return nil
    }
}
#endif
