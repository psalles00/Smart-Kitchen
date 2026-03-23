import SwiftUI

struct CookingModeView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0

    private var sortedSteps: [RecipeStep] {
        recipe.steps.sorted { $0.order < $1.order }
    }

    private var isFirstStep: Bool { currentStep == 0 }
    private var isLastStep: Bool { currentStep >= sortedSteps.count - 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                progressBar

                // Step indicators
                stepIndicators
                    .padding(.top, 16)

                Spacer()

                // Step content
                stepContent
                    .padding(.horizontal, 24)

                Spacer()

                // Navigation buttons
                navigationButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fechar", systemImage: "xmark.circle.fill") {
                        dismiss()
                    }
                    .tint(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(currentStep + 1)/\(sortedSteps.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Progress

    private var progressBar: some View {
        GeometryReader { geo in
            let progress = sortedSteps.isEmpty ? 0 : CGFloat(currentStep + 1) / CGFloat(sortedSteps.count)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(.systemGray5))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * progress)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Step Indicators

    private var stepIndicators: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sortedSteps.indices, id: \.self) { index in
                        Circle()
                            .fill(index <= currentStep ? Color.accentColor : Color(.systemGray4))
                            .frame(width: index == currentStep ? 12 : 8, height: index == currentStep ? 12 : 8)
                            .id(index)
                            .onTapGesture {
                                withAnimation { currentStep = index }
                            }
                    }
                }
                .padding(.horizontal, 24)
            }
            .onChange(of: currentStep) {
                withAnimation { proxy.scrollTo(currentStep, anchor: .center) }
            }
        }
    }

    // MARK: - Step Content

    private var stepContent: some View {
        VStack(spacing: 20) {
            if sortedSteps.indices.contains(currentStep) {
                let step = sortedSteps[currentStep]

                Text("Passo \(step.order)")
                    .font(.sectionTitle)
                    .foregroundStyle(.secondary)

                Text(step.instruction)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)

                if let duration = step.durationMinutes, duration > 0 {
                    Label("\(duration) minutos", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: .capsule)
                }
            }
        }
        .id(currentStep) // Force transition
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            // Previous
            Button {
                withAnimation { currentStep -= 1 }
            } label: {
                Label("Anterior", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .disabled(isFirstStep)

            // Next / Finish
            Button {
                if isLastStep {
                    dismiss()
                } else {
                    withAnimation { currentStep += 1 }
                }
            } label: {
                Label(
                    isLastStep ? "Finalizar" : "Próximo",
                    systemImage: isLastStep ? "checkmark" : "chevron.right"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
