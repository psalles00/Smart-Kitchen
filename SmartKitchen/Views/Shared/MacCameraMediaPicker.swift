#if os(macOS)
import SwiftUI
@preconcurrency import AVFoundation
import AppKit
import UniformTypeIdentifiers

struct MacCameraMediaPicker: NSViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let mode: RecipeCameraPickerMode
    let onCapture: (PickedRecipeMedia) -> Void

    func makeNSViewController(context: Context) -> MacCameraViewController {
        let vc = MacCameraViewController()
        vc.mode = mode
        vc.onCapture = { media in
            onCapture(media)
            dismiss()
        }
        vc.onCancel = {
            dismiss()
        }
        return vc
    }

    func updateNSViewController(_ nsViewController: MacCameraViewController, context: Context) {}
}

final class MacCameraViewController: NSViewController {
    var mode: RecipeCameraPickerMode = .photoOnly
    var onCapture: ((PickedRecipeMedia) -> Void)?
    var onCancel: (() -> Void)?

    private nonisolated(unsafe) var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 520))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    private func setupCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.configureSession()
                } else {
                    self?.showPermissionDenied()
                }
            }
        }
    }

    private func configureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showNoCameraAvailable()
            return
        }

        guard session.canAddInput(input) else { return }
        session.addInput(input)

        let photo = AVCapturePhotoOutput()
        guard session.canAddOutput(photo) else { return }
        session.addOutput(photo)
        self.photoOutput = photo

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = CGRect(x: 0, y: 60, width: view.bounds.width, height: view.bounds.height - 60)
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = CALayer()
        view.wantsLayer = true
        view.layer?.addSublayer(preview)
        self.previewLayer = preview

        self.captureSession = session

        addControls()

        let capturedSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            capturedSession.startRunning()
        }
    }

    private func addControls() {
        let controlsView = NSView(frame: NSRect(x: 0, y: 0, width: view.bounds.width, height: 60))
        controlsView.autoresizingMask = [.width]
        controlsView.wantsLayer = true
        controlsView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        view.addSubview(controlsView)

        let captureButton = NSButton(
            title: "Capturar",
            target: self,
            action: #selector(capturePhoto)
        )
        captureButton.bezelStyle = .rounded
        captureButton.contentTintColor = .white
        captureButton.bezelColor = .controlAccentColor
        captureButton.frame = NSRect(
            x: (view.bounds.width - 100) / 2,
            y: 14,
            width: 100,
            height: 32
        )
        captureButton.autoresizingMask = [.minXMargin, .maxXMargin]
        controlsView.addSubview(captureButton)

        let cancelButton = NSButton(
            title: "Cancelar",
            target: self,
            action: #selector(cancelCapture)
        )
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = NSRect(x: 16, y: 14, width: 80, height: 32)
        controlsView.addSubview(cancelButton)
    }

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput?.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancelCapture() {
        stopSession()
        onCancel?()
    }

    private func stopSession() {
        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            session?.stopRunning()
        }
    }

    private func showPermissionDenied() {
        let label = NSTextField(labelWithString: "Acesso à câmera negado.\nPermita nas Preferências do Sistema.")
        label.alignment = .center
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabelColor
        label.frame = view.bounds
        label.autoresizingMask = [.width, .height]
        view.addSubview(label)
    }

    private func showNoCameraAvailable() {
        let label = NSTextField(labelWithString: "Nenhuma câmera encontrada.")
        label.alignment = .center
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabelColor
        label.frame = view.bounds
        label.autoresizingMask = [.width, .height]
        view.addSubview(label)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopSession()
    }
}

extension MacCameraViewController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }

        // Convert to JPEG for consistency
        if let nsImage = NSImage(data: data),
           let tiff = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            let media = PickedRecipeMedia(type: .photo, data: jpegData, fileExtension: "jpg")
            DispatchQueue.main.async { [weak self] in
                self?.stopSession()
                self?.onCapture?(media)
            }
        }
    }
}
#endif
