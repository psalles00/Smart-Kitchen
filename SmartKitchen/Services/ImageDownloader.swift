import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Utilitário simples para baixar uma imagem hero (URL → Data) e
/// redimensionar para um tamanho razoável antes de gravar no Recipe.
/// Pensado para o fluxo de "Ideias de receitas" da EXA.
enum ImageDownloader {
    /// Tamanho máximo (lado maior) em pontos. Mantém qualidade boa e poupa CloudKit budget.
    static let maxDimension: CGFloat = 1600

    /// Baixa a imagem da URL informada, valida content-type e redimensiona.
    /// Retorna `nil` se URL inválida, content-type não for imagem, ou erro de rede.
    static func fetch(_ urlString: String?) async -> Data? {
        guard let urlString,
              let url = URL(string: urlString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            guard let http = resp as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            // Validar content-type quando disponível.
            if let mime = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
               !mime.contains("image/") {
                return nil
            }
            guard !data.isEmpty else { return nil }
            return resize(data) ?? data
        } catch {
            return nil
        }
    }

    /// Reduz a maior dimensão para `maxDimension`, mantendo proporção.
    /// Retorna JPEG (qualidade 0.85) para boa compressão.
    static func resize(_ data: Data) -> Data? {
        guard let image = PlatformImage(data: data) else { return nil }

        #if canImport(UIKit)
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension else {
            // Já é pequena; só recomprime se for imagem grande em bytes.
            return image.jpegData(compressionQuality: 0.85)
        }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.85)
        #else
        // macOS: redimensiona via NSImage.
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return data }
        let scale = maxDimension / largest
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: .zero,
                   operation: .copy,
                   fraction: 1.0)
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return data }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        #endif
    }
}
