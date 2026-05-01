import SwiftUI

/// Initial splash screen displayed while the app warms up its data layer
/// (SwiftData/CloudKit container, seeders, migrations, backup recovery).
///
/// The splash blocks navigation so the user never lands on a half-loaded
/// dashboard while bootstrap work runs in the background.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            Image("AppLogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 8)
                .accessibilityLabel("Savoria")
        }
        .transition(.opacity)
    }
}

#Preview {
    SplashView()
}
