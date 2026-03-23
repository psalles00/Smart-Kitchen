import SwiftUI

/// Displays an icon from the bundled icon library, falling back to an SF Symbol.
struct IconImage: View {
    let name: String
    var fallbackSymbol: String = "leaf"
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let uiImage = IconResolver.image(for: name) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.55))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
