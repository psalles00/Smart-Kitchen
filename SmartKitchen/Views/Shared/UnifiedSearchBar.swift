import SwiftUI
#if os(iOS)
import PhotosUI
import UIKit
#endif

// MARK: - Unified Search Bar

/// Liquid Glass search bar displayed in the shader area.
/// Uses `.glassEffect()` on iOS 26+, falls back to `.ultraThinMaterial`.
struct UnifiedSearchBar: View {
    @ObservedObject var state: SearchBarState
    let onSubmit: (String) -> Void
    private let chromeHeight: CGFloat = 46

    @FocusState private var isFocused: Bool

    #if os(iOS)
    @State private var showPhotoLibrary = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCameraPicker = false
    @State private var showCameraUnavailableAlert = false
    #endif

    private var isEmpty: Bool {
        state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasTypedText: Bool {
        !state.searchText.isEmpty
    }

    private func requestFocus() {
        if state.isVisible {
            state.focusTrigger += 1
        } else {
            state.reveal(mode: state.mode)
        }
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
        #if os(iOS)
        .photosPicker(isPresented: $showPhotoLibrary, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task {
                await handleSelectedPhoto(newValue)
            }
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraMediaPicker(mode: .photoOnly) { _ in
                appendImageAttachmentHint(source: "camera")
            }
            .forceLightStatusBar()
        }
        .alert("Câmera indisponível", isPresented: $showCameraUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Este dispositivo não permite capturar fotos no momento.")
        }
        #endif
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: state.mode == .aiChat ? "paperplane.fill" : "sparkle.magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(state.mode == .aiChat ? "Converse com a IA…" : "Assistente", text: $state.searchText)
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
                            state.pendingChatMessage = trimmed
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

            if state.isVisible {
                closeButton
            }
        }
    }

    @ViewBuilder
    private var accessoryActions: some View {
        if hasTypedText {
            collapsedAccessoryMenu
        } else {
            expandedAccessoryActions
        }
    }

    private var collapsedAccessoryMenu: some View {
        Menu {
            #if os(iOS)
            Button("Registrar com Voz", systemImage: "mic.fill") {
                startDictation()
            }
            #endif

            Button("Registrar com Galeria", systemImage: "photo.on.rectangle") {
                openPhotoLibrary()
            }

            Button("Registrar com Câmera", systemImage: "camera") {
                openCamera()
            }

            Section("Nutrição") {
                Button("Foto da refeição", systemImage: "camera.fill") {
                    presentNutritionSheet(.capturePhoto)
                }
                Button("Rótulo nutricional", systemImage: "doc.text.viewfinder") {
                    presentNutritionSheet(.captureLabel)
                }
                Button("Registrar por voz", systemImage: "waveform") {
                    presentNutritionSheet(.captureVoice)
                }
                Button("Descrever por texto", systemImage: "text.alignleft") {
                    presentNutritionSheet(.captureText)
                }
                Button("Entrada manual", systemImage: "square.and.pencil") {
                    presentNutritionSheet(.manual)
                }
                Button("Recentes / frequentes", systemImage: "clock.arrow.circlepath") {
                    presentNutritionSheet(.recents)
                }
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .tint(Color.secondary)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private var expandedAccessoryActions: some View {
        Menu {
            Button("Foto da refeição", systemImage: "camera.fill") {
                presentNutritionSheet(.capturePhoto)
            }
            Button("Rótulo nutricional", systemImage: "doc.text.viewfinder") {
                presentNutritionSheet(.captureLabel)
            }
            Button("Registrar por voz", systemImage: "waveform") {
                presentNutritionSheet(.captureVoice)
            }
            Button("Descrever por texto", systemImage: "text.alignleft") {
                presentNutritionSheet(.captureText)
            }
            Button("Entrada manual", systemImage: "square.and.pencil") {
                presentNutritionSheet(.manual)
            }
            Button("Recentes / frequentes", systemImage: "clock.arrow.circlepath") {
                presentNutritionSheet(.recents)
            }
        } label: {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .tint(Color.secondary)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)

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

        Button {
            openPhotoLibrary()
        } label: {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)

        Button {
            openCamera()
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button(role: .cancel) {
            state.dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: chromeHeight, height: chromeHeight)
                .contentShape(Circle())
        }
        .accessibilityLabel("Fechar")
        .modifier(NativeGlassCloseButtonModifier())
        .transition(.move(edge: .trailing).combined(with: .opacity))
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

    // MARK: - Dictation

    #if os(iOS)
    private func openPhotoLibrary() {
        showPhotoLibrary = true
    }

    private func openCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCameraPicker = true
        } else {
            showCameraUnavailableAlert = true
        }
    }

    private func startDictation() {
        // Keep to native keyboard dictation flow by focusing the field only.
        // Triggering dictation via private selectors is brittle and can cause
        // runtime issues/warnings across iOS versions and simulator runtimes.
        isFocused = true
    }

    private func handleSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        _ = try? await item.loadTransferable(type: Data.self)
        await MainActor.run {
            appendImageAttachmentHint(source: "gallery")
            selectedPhotoItem = nil
        }
    }

    private func appendImageAttachmentHint(source: String) {
        let token = source == "camera" ? "[foto]" : "[imagem]"
        if state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.searchText = "Analise esta \(token)"
            return
        }
        if !state.searchText.contains(token) {
            state.searchText += " \(token)"
        }
    }
    #else
    private func openPhotoLibrary() { }

    private func openCamera() { }
    #endif

    private func presentNutritionSheet(_ sheet: NutritionEntrySheet) {
        state.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            state.pendingNutritionSheet = sheet
        }
    }
}

private struct NativeGlassCloseButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content
                .buttonStyle(.plain)
                .contentShape(Circle())
                .background {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .allowsHitTesting(false)
                }
        } else {
            content
                .buttonStyle(.plain)
                .contentShape(Circle())
                .background(.ultraThinMaterial, in: Circle())
        }
    }
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
