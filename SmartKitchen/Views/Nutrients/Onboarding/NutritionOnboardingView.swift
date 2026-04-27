import SwiftUI
import SwiftData

/// Onboarding curto (6 etapas) para coletar dados básicos e calcular metas nutricionais.
/// Apresentado como sheet; ao concluir marca `hasCompletedOnboarding = true`.
struct NutritionOnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 0

    // Dados coletados
    @State private var sex: NutritionSex = .other
    @State private var birthday: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var heightCm: Double = 170
    @State private var weightKg: Double = 70
    @State private var activityLevel: ActivityLevel = .moderate
    @State private var weightGoal: WeightGoal = .maintain
    @State private var weeklyChangeKg: Double = 0.5

    private let totalSteps = 6
    private var theme: PageTheme { .nutrients }

    var body: some View {
        ZStack {
            theme.gradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                TabView(selection: $step) {
                    sexStep.tag(0)
                    birthdayStep.tag(1)
                    bodyStep.tag(2)
                    activityStep.tag(3)
                    goalStep.tag(4)
                    reviewStep.tag(5)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .animation(.easeInOut(duration: 0.25), value: step)

                footer
            }
        }
        .tint(.white)
    }

    // MARK: - Header (progress + close)

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.18), in: .circle)
                }
                Spacer()
                Text("Configurar Nutrição")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }

            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.white : Color.white.opacity(0.25))
                        .frame(height: 4)
                        .animation(.easeInOut(duration: 0.2), value: step)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Footer (continue / back)

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    Text("Voltar")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.15), in: .capsule)
                }
            }

            Button {
                if step < totalSteps - 1 {
                    withAnimation { step += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(step == totalSteps - 1 ? "Concluir" : "Continuar")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white, in: .capsule)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    // MARK: - Step 0: Sex

    private var sexStep: some View {
        stepContainer(title: "Qual é o seu sexo?",
                      subtitle: "Usamos para calcular seu metabolismo basal (BMR).") {
            VStack(spacing: 12) {
                ForEach(NutritionSex.allCases) { option in
                    choiceRow(
                        title: option.displayName,
                        subtitle: nil,
                        icon: option.icon,
                        isSelected: sex == option
                    ) {
                        sex = option
                    }
                }
            }
        }
    }

    // MARK: - Step 1: Birthday

    private var birthdayStep: some View {
        stepContainer(title: "Quando você nasceu?",
                      subtitle: "Usamos sua idade no cálculo de calorias diárias.") {
            VStack(spacing: 16) {
                DatePicker(
                    "Data de nascimento",
                    selection: $birthday,
                    in: ...(.now),
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.white.opacity(0.95), in: .rect(cornerRadius: 20))
                .colorScheme(.light)

                Text("\(ageYears(from: birthday)) anos")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Step 2: Body (height + weight)

    private var bodyStep: some View {
        stepContainer(title: "Altura e peso",
                      subtitle: "Você pode atualizar a qualquer momento em Ajustes.") {
            VStack(spacing: 20) {
                measurementCard(
                    title: "Altura",
                    value: String(format: "%.0f cm", heightCm),
                    binding: $heightCm,
                    range: 120...220,
                    step: 1
                )

                measurementCard(
                    title: "Peso",
                    value: String(format: "%.1f kg", weightKg),
                    binding: $weightKg,
                    range: 30...250,
                    step: 0.5
                )
            }
        }
    }

    // MARK: - Step 3: Activity

    private var activityStep: some View {
        stepContainer(title: "Nível de atividade",
                      subtitle: "Nos ajuda a estimar quanto você queima por dia.") {
            VStack(spacing: 10) {
                ForEach(ActivityLevel.allCases) { level in
                    choiceRow(
                        title: level.displayName,
                        subtitle: level.subtitle,
                        icon: "flame.fill",
                        isSelected: activityLevel == level
                    ) {
                        activityLevel = level
                    }
                }
            }
        }
    }

    // MARK: - Step 4: Weight goal

    private var goalStep: some View {
        stepContainer(title: "Qual seu objetivo?",
                      subtitle: weightGoal == .maintain
                        ? "Vamos manter seu peso atual."
                        : "Defina quantos kg por semana.") {
            VStack(spacing: 12) {
                ForEach(WeightGoal.allCases) { goal in
                    choiceRow(
                        title: goal.displayName,
                        subtitle: nil,
                        icon: goal.icon,
                        isSelected: weightGoal == goal
                    ) {
                        weightGoal = goal
                    }
                }

                if weightGoal != .maintain {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Velocidade")
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer()
                            Text(String(format: "%.2f kg/semana", weeklyChangeKg))
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        Slider(value: $weeklyChangeKg, in: 0.1...1.0, step: 0.05)
                            .tint(.white)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.12), in: .rect(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - Step 5: Review

    private var reviewStep: some View {
        stepContainer(title: "Seu plano está pronto",
                      subtitle: "Você pode ajustar tudo depois em Ajustes.") {
            let preview = previewProfile()
            VStack(spacing: 12) {
                statCard(
                    title: "Calorias por dia",
                    value: "\(preview.effectiveCalories) kcal",
                    icon: "flame.fill"
                )

                HStack(spacing: 12) {
                    macroStat(title: "Proteína", grams: preview.effectiveProteinG)
                    macroStat(title: "Carbos", grams: preview.effectiveCarbsG)
                    macroStat(title: "Gordura", grams: preview.effectiveFatG)
                }

                VStack(alignment: .leading, spacing: 6) {
                    reviewLine(label: "Sexo", value: localizedString(sex.displayName))
                    reviewLine(label: "Idade", value: "\(ageYears(from: birthday)) anos")
                    reviewLine(label: "Altura", value: String(format: "%.0f cm", heightCm))
                    reviewLine(label: "Peso", value: String(format: "%.1f kg", weightKg))
                    reviewLine(label: "Atividade", value: localizedString(activityLevel.displayName))
                    reviewLine(label: "Objetivo", value: localizedString(weightGoal.displayName))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.12), in: .rect(cornerRadius: 16))
            }
        }
    }

    // MARK: - Helpers

    private func stepContainer<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.pageTitle)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.serifBody)
                        .foregroundStyle(.white.opacity(0.85))
                }
                content()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func choiceRow(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey?,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? theme.accentColor : .white)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Color.white : Color.white.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.1),
                in: .rect(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.55 : 0), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    private func measurementCard(
        title: String,
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            Slider(value: binding, in: range, step: step)
                .tint(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.12), in: .rect(cornerRadius: 16))
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(theme.accentColor)
                .frame(width: 44, height: 44)
                .background(.white, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.12), in: .rect(cornerRadius: 16))
    }

    private func macroStat(title: String, grams: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(grams) g")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.12), in: .rect(cornerRadius: 16))
    }

    private func reviewLine(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Logic

    private func ageYears(from date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.year], from: date, to: .now)
        return max(comps.year ?? 0, 0)
    }

    /// Perfil temporário em memória para pré-visualizar macros na última etapa.
    private func previewProfile() -> NutritionProfile {
        let p = NutritionProfile(
            sex: sex,
            birthday: birthday,
            heightCm: heightCm,
            weightKg: weightKg,
            activityLevel: activityLevel,
            weightGoal: weightGoal
        )
        p.weeklyChangeKg = weightGoal == .maintain ? 0 : weeklyChangeKg
        return p
    }

    private func finish() {
        let profile = NutritionProfileStore.fetchOrCreate(in: modelContext)
        profile.sex = sex
        profile.birthday = birthday
        profile.heightCm = heightCm
        profile.weightKg = weightKg
        profile.activityLevel = activityLevel
        profile.weightGoal = weightGoal
        profile.weeklyChangeKg = weightGoal == .maintain ? 0 : weeklyChangeKg
        profile.hasCompletedOnboarding = true
        profile.updatedAt = .now
        try? modelContext.save()

        // Registra o peso atual também como primeiro WeightEntry.
        let weightEntry = WeightEntry(date: .now, weightKg: weightKg)
        modelContext.insert(weightEntry)
        try? modelContext.save()

        dismiss()
    }

    /// Converte um `LocalizedStringKey` em `String` para interpolação simples.
    /// Para strings estáticas em pt-BR basta espelhar o texto do `.displayName`.
    private func localizedString(_ key: LocalizedStringKey) -> String {
        let mirror = Mirror(reflecting: key)
        for child in mirror.children where child.label == "key" {
            if let str = child.value as? String { return str }
        }
        return ""
    }
}

#Preview {
    NutritionOnboardingView()
        .modelContainer(for: [NutritionProfile.self, WeightEntry.self, FoodEntry.self, NutritionDayLog.self], inMemory: true)
}
