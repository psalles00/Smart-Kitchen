import SwiftUI

/// Full-screen processing animation shown while the import pipeline runs.
struct RecipeImportProcessingView: View {
    let stage: RecipeImportStage
    let onCancel: () -> Void

    @State private var pulsate = false

    private let allStages: [RecipeImportStage] = [
        .analyzing, .fetching, .extractingText, .organizingIngredients, .finalizing
    ]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                // Outer halo
                Circle()
                    .fill(PageTheme.recipes.accentColor.opacity(0.12))
                    .frame(width: 180, height: 180)
                    .scaleEffect(pulsate ? 1.05 : 0.95)
                    .blur(radius: 18)

                Circle()
                    .fill(PageTheme.recipes.accentColor.opacity(0.24))
                    .frame(width: 130, height: 130)
                    .scaleEffect(pulsate ? 1.08 : 0.92)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [PageTheme.recipes.accentColor, PageTheme.recipes.secondaryAccentColor],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: stage.systemImage)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulsate = true
                }
            }

            VStack(spacing: 6) {
                Text(stage.title)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: stage)

                Text("Deixa com a gente — isso leva só alguns segundos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Progress track
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.secondarySystemBackground))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [PageTheme.recipes.accentColor, PageTheme.recipes.secondaryAccentColor],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(12, proxy.size.width * stage.progress))
                        .animation(.easeInOut(duration: 0.45), value: stage)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 32)
            .padding(.top, 8)

            // Stage checklist
            VStack(alignment: .leading, spacing: 10) {
                ForEach(allStages, id: \.title) { s in
                    HStack(spacing: 12) {
                        Image(systemName: completed(s) ? "checkmark.circle.fill" : (current(s) ? "circle.dotted" : "circle"))
                            .font(.body.weight(.medium))
                            .foregroundStyle(completed(s) ? PageTheme.recipes.accentColor : (current(s) ? Color.primary : Color.secondary.opacity(0.6)))
                            .contentTransition(.symbolEffect(.replace))
                        Text(s.title)
                            .font(.subheadline.weight(current(s) ? .semibold : .regular))
                            .foregroundStyle(completed(s) ? .primary : (current(s) ? .primary : .secondary))
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)

            Spacer()

            Button(role: .cancel, action: onCancel) {
                Text("Cancelar")
                    .font(.body.weight(.medium))
            }
            .tint(.secondary)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func index(of s: RecipeImportStage) -> Int {
        allStages.firstIndex(where: { $0.title == s.title }) ?? 0
    }

    private func completed(_ s: RecipeImportStage) -> Bool {
        index(of: s) < index(of: stage)
    }

    private func current(_ s: RecipeImportStage) -> Bool {
        s.title == stage.title
    }
}
