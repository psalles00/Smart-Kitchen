import SwiftUI

/// Tela de loading enquanto a IA analisa texto, foto ou rótulo.
struct FoodAnalyzingView: View {
    var image: PlatformImage? = nil
    var message: String = "Analisando sua refeição…"

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if let image {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 240)
                    .clipShape(.rect(cornerRadius: 16))
                    .shadow(radius: 8, y: 2)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(PageTheme.nutrients.gradient)
            }

            ProgressView()
                .controlSize(.large)
                .tint(PageTheme.nutrients.accentColor)

            Text(message)
                .font(.headline)
                .foregroundStyle(PageTheme.nutrients.accentColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
