import SwiftUI
import SwiftData

/// Root coordinator for the first-launch onboarding flow. Hosts every step
/// and is the single point that flips `AppSettings.hasCompletedOnboarding` to
/// `true` once the user finishes (or chooses the free plan on the paywall).
struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var state = OnboardingState()
    /// Driven by `state.stepIndex` but mirrored locally so SwiftUI can animate
    /// transitions reliably across view-tree rebuilds.
    @State private var displayedStepIndex: Int = 0
    /// Guards against running the SwiftData commit twice (preparing screen
    /// kicks it off, paywall completion would otherwise repeat it).
    @State private var didCommitChoices: Bool = false

    let onFinish: () -> Void

    var body: some View {
        ZStack {
            // Soft adaptive backdrop. Specific steps may overlay their own
            // shaders / hero graphics on top.
            backgroundLayer
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if showsProgressBar {
                    OnboardingProgressBar(
                        progress: progressFraction,
                        canGoBack: state.stepIndex > 0,
                        onBack: goBack
                    )
                }

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(state.stepIndex) // forces transition between steps
                    .transition(stepTransition)
            }
        }
        .preferredColorScheme(nil) // follow system
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: state.stepIndex)
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        // Subtle adaptive gradient background. Hero/welcome step can opt-in
        // to the Nebula shader by overlaying its own background.
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(white: 0.06), Color(white: 0.10)]
                : [Color(white: 0.99), Color(white: 0.94)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        let step = OnboardingStep(rawValue: state.stepIndex) ?? .welcome
        switch step {
        case .welcome:
            WelcomeStepView(onContinue: advance)
        case .recipes:
            RecipesIntroStepView(onContinue: advance)
        case .pantryShopping:
            PantryShoppingIntroStepView(onContinue: advance)
        case .nutritionAndAI:
            NutritionAIIntroStepView(onContinue: advance)
        case .selectPantry:
            SelectPantryStepView(state: state, onContinue: advance)
        case .selectGrocery:
            SelectGroceryStepView(state: state, onContinue: advance)
        case .selectRecipes:
            SelectRecipesStepView(state: state, onContinue: advance)
        case .tutorialPantryToGrocery:
            TutorialPantryToGroceryStepView(state: state, onContinue: advance)
        case .tutorialGroceryToPantry:
            TutorialGroceryToPantryStepView(state: state, onContinue: advance)
        case .tutorialShareAndPin:
            TutorialShareAndPinStepView(onContinue: advance)
        case .goal:
            GoalStepView(state: state, onContinue: advance)
        case .sex:
            SexStepView(state: state, onContinue: advance)
        case .birthday:
            BirthdayStepView(state: state, onContinue: advance)
        case .body:
            BodyStepView(state: state, onContinue: advance)
        case .activity:
            ActivityStepView(state: state, onContinue: advance)
        case .rate:
            RateStepView(state: state, onContinue: advance)
        case .preparing:
            PreparingStepView(onFinished: {
                // Commit data while the animation plays out, then advance to paywall.
                commitOnboardingChoices(subscribed: false)
                advance()
            })
        case .paywall:
            PaywallStepView(state: state, onFinish: { subscribed in
                finishOnboarding(subscribed: subscribed)
            })
        }
    }

    // MARK: - Navigation

    private var progressFraction: Double {
        let total = max(1, OnboardingStep.allCases.count - 1)
        return Double(state.stepIndex) / Double(total)
    }

    /// Hide the progress bar on the very first hero/welcome step so the
    /// fullscreen Nebula shader has no UI chrome floating on top of it.
    private var showsProgressBar: Bool {
        state.stepIndex != OnboardingStep.welcome.rawValue
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func advance() {
        let next = state.stepIndex + 1
        guard next < OnboardingStep.allCases.count else {
            finishOnboarding(subscribed: false)
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            state.stepIndex = next
        }
    }

    private func goBack() {
        guard state.stepIndex > 0 else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            state.stepIndex -= 1
        }
    }

    /// Commits everything to the database and dismisses the flow.
    /// Phase 0 ships with a no-op commit (the placeholder steps don't touch
    /// the DB yet); later phases will fill `commitOnboardingChoices` in.
    private func finishOnboarding(subscribed: Bool) {
        commitOnboardingChoices(subscribed: subscribed)
        markOnboardingComplete()
        onFinish()
    }

    private func commitOnboardingChoices(subscribed: Bool) {
        guard !didCommitChoices else { return }
        didCommitChoices = true

        // Insert NutritionProfile from the captured choices.
        let goal = WeightGoal(rawValue: state.nutritionGoalRaw ?? "") ?? .maintain
        let profile = NutritionProfile(
            sex: NutritionSex(rawValue: state.nutritionSexRaw ?? "") ?? .other,
            birthday: state.nutritionBirthday,
            heightCm: state.nutritionHeightCm,
            weightKg: state.nutritionWeightKg,
            activityLevel: ActivityLevel(rawValue: state.nutritionActivityRaw ?? "") ?? .moderate,
            weightGoal: goal
        )
        profile.weeklyChangeKg = state.nutritionWeeklyChangeKg * (goal == .lose ? -1 : 1)
        profile.hasCompletedOnboarding = true
        modelContext.insert(profile)

        // Insert pantry selections.
        for (index, id) in state.selectedPantryItemIDs.enumerated() {
            guard let template = OnboardingCatalog.pantryItems.first(where: { $0.id == id }) else { continue }
            let item = UnifiedItem(
                name: template.displayName,
                category: template.category,
                iconName: template.iconFileName,
                isPantry: true,
                pantrySortOrder: index
            )
            modelContext.insert(item)
        }

        // Insert grocery selections.
        for (index, id) in state.selectedGroceryItemIDs.enumerated() {
            guard let template = OnboardingCatalog.groceryItems.first(where: { $0.id == id }) else { continue }
            let item = UnifiedItem(
                name: template.displayName,
                category: template.category,
                iconName: template.iconFileName,
                isGrocery: true,
                grocerySortOrder: index
            )
            modelContext.insert(item)
        }

        // Insert recipe templates with their full ingredient/step graphs.
        for id in state.selectedRecipeTemplateIDs {
            guard let template = OnboardingCatalog.recipeTemplates.first(where: { $0.id == id }) else { continue }
            let recipe = Recipe(
                name: template.name,
                descriptionText: template.summary,
                category: template.category,
                tags: template.tags,
                prepTime: template.prepMinutes,
                cookTime: template.cookMinutes,
                servings: template.servings,
                calories: template.calories,
                difficulty: .easy
            )
            modelContext.insert(recipe)

            for (order, tuple) in template.ingredients.enumerated() {
                let ing = RecipeIngredient(
                    name: tuple.0,
                    quantity: tuple.1,
                    unit: tuple.2,
                    iconName: tuple.3,
                    sortOrder: order
                )
                ing.recipe = recipe
                modelContext.insert(ing)
            }

            for (index, instruction) in template.steps.enumerated() {
                let step = RecipeStep(order: index + 1, instruction: instruction)
                step.recipe = recipe
                modelContext.insert(step)
            }
        }
    }

    private func markOnboardingComplete() {
        let descriptor = FetchDescriptor<AppSettings>()
        let settings = (try? modelContext.fetch(descriptor))?.first
        if let settings {
            settings.hasCompletedOnboarding = true
        } else {
            let new = AppSettings()
            new.hasCompletedOnboarding = true
            modelContext.insert(new)
        }
        try? modelContext.save()
    }
}

// MARK: - Phase 0 placeholder

/// Temporary single-view renderer used while the per-step views are being
/// authored across phases. Each later phase replaces a slice of this `switch`
/// with a dedicated step view (e.g. `WelcomeStepView`, `SelectPantryStepView`).
private struct OnboardingPlaceholderStepView: View {
    let step: OnboardingStep
    let state: OnboardingState
    let onAdvance: () -> Void
    let onFinish: (Bool) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            OnboardingHeader(
                title: stepTitle,
                subtitle: stepSubtitle
            )

            Spacer()

            VStack(spacing: 12) {
                OnboardingPrimaryButton(
                    title: step.isLast
                        ? String(localized: "Continuar com versão grátis")
                        : String(localized: "Continuar"),
                    action: {
                        if step.isLast {
                            onFinish(false)
                        } else {
                            onAdvance()
                        }
                    }
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // Friendly placeholder copy per step. Each phase will replace these views
    // entirely; these strings are dev-only and not added to the localisation
    // catalogue on purpose.
    private var stepTitle: String {
        switch step {
        case .welcome: return "Bem-vindo ao Smart Kitchen"
        case .recipes: return "Suas receitas, organizadas"
        case .pantryShopping: return "Despensa e mercado conectados"
        case .nutritionAndAI: return "Calorias sem culpa, com IA"
        case .selectPantry: return "Escolha sua despensa inicial"
        case .selectGrocery: return "Sua primeira lista de compras"
        case .selectRecipes: return "O que você gosta de cozinhar?"
        case .tutorialPantryToGrocery: return "Mover para o mercado"
        case .tutorialGroceryToPantry: return "Comprou? Vai pra despensa"
        case .tutorialShareAndPin: return "Importe das redes sociais"
        case .goal: return "Qual o seu objetivo?"
        case .sex: return "Sobre você"
        case .birthday: return "Quando você nasceu?"
        case .body: return "Altura e peso"
        case .activity: return "Nível de atividade"
        case .rate: return "Ritmo da mudança"
        case .preparing: return "Preparando seu app…"
        case .paywall: return "Smart Kitchen Premium"
        }
    }

    private var stepSubtitle: String? {
        step == .welcome ? "Esta é uma visualização de desenvolvimento. As telas finais virão nas próximas fases." : nil
    }
}
