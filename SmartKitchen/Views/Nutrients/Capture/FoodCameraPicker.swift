#if os(iOS)
import SwiftUI
import UIKit

/// Câmera simples para capturar UMA foto — usada em "Foto da refeição" e "Rótulo nutricional".
struct FoodCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coord { Coord(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.cameraCaptureMode = .photo
        p.allowsEditing = false
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coord: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: FoodCameraPicker
        init(_ p: FoodCameraPicker) { self.parent = p }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.onCapture(img)
            }
            parent.dismiss()
        }
    }
}
#endif
