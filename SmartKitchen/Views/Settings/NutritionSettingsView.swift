import SwiftUI
import SwiftData

/// Subpágina de configurações de Nutrição — corpo, metas, overrides, unidades e preferências.
/// Apresentada via NavigationLink a partir de `SettingsView` (Seção dedicada).
struct NutritionSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \NutritionProfile.createdAt) private var profiles: [NutritionProfile]
    @State private var showRedoOnboarding = false
    @State private var showResetConfirmation = false

    private var profile: NutritionProfile? { profiles.first }

    var body: some View {
        Form {
            if let profile, profile.hasCompletedOnboarding {
                bodySection(profile: profile)
                goalSection(profile: profile)
                overridesSection(profile: profile)
                preferencesSection(profile: profile)
                computedSection(profile: profile)
                actionsSection
            } else {
                emptyOnboardingSection
            }
        }
        .settingsFormStyle()
        .settingsNavigationTitle(String(localized: "Nutrição"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .tint(PageTheme.nutrients.accentColor)
        .sheet(isPresented: $showRedoOnboarding) {
            NutritionOnboardingHostView()
        }
        .alert("Redefinir perfil de nutrição?", isPresented: $showResetConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Redefinir", role: .destructive) {
                resetProfile()
            }
        } message: {
            Text("Isso apagará as metas, overrides e preferências do perfil atual. Seus registros de refeições e peso permanecem intactos.")
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyOnboardingSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(PageTheme.nutrients.gradient)
                Text("Configure seu perfil")
                    .font(.sectionTitle)
                Text("Responda 6 perguntas rápidas para calcularmos suas metas diárias.")
                    .font(.serifBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showRedoOnboarding = true
                } label: {
                    Text("Começar")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(PageTheme.nutrients.gradient, in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func bodySection(profile: NutritionProfile) -> some View {
        Section("Corpo") {
            Picker("Sexo", selection: Binding(
                get: { profile.sex },
                set: { profile.sex = $0 }
            )) {
                ForEach(NutritionSex.allCases) { s in
                    Text(s.displayName).tag(s)
                }
            }

            DatePicker(
                "Aniversário",
                selection: Binding(
                    get: { profile.birthday ?? Date(timeIntervalSinceNow: -30 * 365 * 86400) },
                    set: { profile.birthday = $0; profile.updatedAt = .now }
                ),
                in: ...Date(),
                displayedComponents: .date
            )

            Stepper(
                value: Binding(
                    get: { profile.heightCm },
                    set: { profile.heightCm = $0; profile.updatedAt = .now }
                ),
                in: 100...230,
                step: 1
            ) {
                LabeledContent("Altura") {
                    Text("\(Int(profile.heightCm)) cm")
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(
                value: Binding(
                    get: { profile.weightKg },
                    set: { profile.weightKg = $0; profile.updatedAt = .now }
                ),
                in: 30...250,
                step: 0.5
            ) {
                LabeledContent("Peso atual") {
                    Text(String(format: "%.1f kg", profile.weightKg))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Goal

    @ViewBuilder
    private func goalSection(profile: NutritionProfile) -> some View {
        Section("Objetivo") {
            Picker("Meta", selection: Binding(
                get: { profile.weightGoal },
                set: { profile.weightGoal = $0 }
            )) {
                ForEach(WeightGoal.allCases) { g in
                    Text(g.displayName).tag(g)
                }
            }

            Picker("Atividade", selection: Binding(
                get: { profile.activityLevel },
                set: { profile.activityLevel = $0 }
            )) {
                ForEach(ActivityLevel.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }

            if profile.weightGoal != .maintain {
                Stepper(
                    value: Binding(
                        get: { profile.weeklyChangeKg },
                        set: { profile.weeklyChangeKg = $0; profile.updatedAt = .now }
                    ),
                    in: -1.0...1.0,
                    step: 0.1
                ) {
                    LabeledContent("Ritmo semanal") {
                        Text(String(format: "%+.1f kg/semana", profile.weeklyChangeKg))
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(
                    value: Binding(
                        get: { profile.targetWeightKg ?? profile.weightKg },
                        set: { profile.targetWeightKg = $0; profile.updatedAt = .now }
                    ),
                    in: 30...250,
                    step: 0.5
                ) {
                    LabeledContent("Peso desejado") {
                        Text(String(format: "%.1f kg", profile.targetWeightKg ?? profile.weightKg))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Overrides

    @ViewBuilder
    private func overridesSection(profile: NutritionProfile) -> some View {
        Section {
            overrideRow(
                label: "Calorias (kcal)",
                value: Binding(
                    get: { profile.overrideCalories },
                    set: { profile.overrideCalories = $0; profile.updatedAt = .now }
                ),
                placeholder: "\(NutritionCalculations.targetCalories(profile: profile))"
            )
            overrideRow(
                label: "Proteína (g)",
                value: Binding(
                    get: { profile.overrideProteinG },
                    set: { profile.overrideProteinG = $0; profile.updatedAt = .now }
                ),
                placeholder: "\(NutritionCalculations.targetProteinG(profile: profile))"
            )
            overrideRow(
                label: "Carbos (g)",
                value: Binding(
                    get: { profile.overrideCarbsG },
                    set: { profile.overrideCarbsG = $0; profile.updatedAt = .now }
                ),
                placeholder: "—"
            )
            overrideRow(
                label: "Gordura (g)",
                value: Binding(
                    get: { profile.overrideFatG },
                    set: { profile.overrideFatG = $0; profile.updatedAt = .now }
                ),
                placeholder: "—"
            )
        } header: {
            Text("Metas personalizadas")
        } footer: {
            Text("Deixe em branco para usar os valores calculados automaticamente a partir do seu corpo e objetivo.")
        }
    }

    private func overrideRow(label: String, value: Binding<Int?>, placeholder: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, value: value, format: .number)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .frame(maxWidth: 90)
        }
    }

    // MARK: - Preferences

    @ViewBuilder
    private func preferencesSection(profile: NutritionProfile) -> some View {
        Section("Preferências") {
            Toggle("Unidades métricas (kg / cm)", isOn: Binding(
                get: { profile.useMetric },
                set: { profile.useMetric = $0; profile.updatedAt = .now }
            ))
            Toggle("Semana começa na segunda-feira", isOn: Binding(
                get: { profile.weekStartsOnMonday },
                set: { profile.weekStartsOnMonday = $0; profile.updatedAt = .now }
            ))
        }
    }

    // MARK: - Computed targets

    @ViewBuilder
    private func computedSection(profile: NutritionProfile) -> some View {
        Section("Metas efetivas") {
            LabeledContent("Calorias") {
                Text("\(profile.effectiveCalories) kcal")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Proteína") {
                Text("\(profile.effectiveProteinG) g")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Carbos") {
                Text("\(profile.effectiveCarbsG) g")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Gordura") {
                Text("\(profile.effectiveFatG) g")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            Button {
                showRedoOnboarding = true
            } label: {
                Label("Refazer onboarding", systemImage: "arrow.counterclockwise")
            }

            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Redefinir perfil", systemImage: "trash")
            }
        }
    }

    private func resetProfile() {
        guard let profile else { return }
        profile.overrideCalories = nil
        profile.overrideProteinG = nil
        profile.overrideCarbsG = nil
        profile.overrideFatG = nil
        profile.hasCompletedOnboarding = false
        profile.updatedAt = .now
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        NutritionSettingsView()
    }
    .modelContainer(for: NutritionProfile.self, inMemory: true)
}
