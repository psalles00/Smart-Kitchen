import SwiftUI
import CloudKit

// MARK: - Cross-platform CloudKit Sharing Controller

struct CloudSharingControllerView: View {
    let share: CKShare
    let container: CKContainer

    var body: some View {
        #if os(iOS)
        CloudSharingControllerRepresentable(share: share, container: container)
            .ignoresSafeArea()
        #else
        MacSharingView(share: share, container: container)
        #endif
    }
}

// MARK: - iOS: UICloudSharingController wrapper

#if os(iOS)
struct CloudSharingControllerRepresentable: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            Task { @MainActor in
                await SharingService.shared.refreshShare()
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in
                SharingService.shared.isSharing = false
                SharingService.shared.activeShare = nil
                SharingService.shared.participants = []
            }
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Task { @MainActor in
                SharingService.shared.error = error.localizedDescription
            }
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "Smart Kitchen"
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            nil
        }
    }
}
#endif

// MARK: - macOS: Custom Sharing Sheet

#if os(macOS)
struct MacSharingView: View {
    let share: CKShare
    let container: CKContainer
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(.purple)

            Text("Compartilhar Smart Kitchen")
                .font(.headline)

            Text("Envie o link abaixo para convidar participantes. Eles precisam ter iCloud ativo.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let url = share.url {
                GroupBox {
                    HStack {
                        Text(url.absoluteString)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copied = false
                            }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(4)
                }

                if copied {
                    Text("Link copiado!")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                HStack(spacing: 12) {
                    Button {
                        let service = NSSharingService(named: .composeMessage)
                        service?.perform(withItems: [url])
                    } label: {
                        Label("Mensagens", systemImage: "message")
                    }

                    Button {
                        let service = NSSharingService(named: .composeEmail)
                        service?.perform(withItems: [url])
                    } label: {
                        Label("E-mail", systemImage: "envelope")
                    }
                }
            } else {
                Text("Link de compartilhamento não disponível.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button("Fechar") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 400, height: 340)
    }
}
#endif
