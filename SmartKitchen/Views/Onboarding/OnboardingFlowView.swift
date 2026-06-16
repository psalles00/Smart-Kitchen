import StoreKit
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
    @State private var subscriptionManager = SubscriptionManager()
    @State private var restorePromptTitle = ""
    @State private var showRestorePrompt = false
    @State private var restoreFeedbackMessage = ""
    @State private var showRestoreFeedbackAlert = false

    private var cloudSync = CloudSyncService.shared

    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            // Soft adaptive backdrop. Specific steps may overlay their own
            // full-screen hero graphics on top.
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
        .alert(restorePromptTitle, isPresented: $showRestorePrompt) {
            Button(String(localized: "Continuar"), role: .cancel) {}
            Button(restorePromptButtonTitle) {
                finishOnboarding(
                    subscribed: true,
                    skippingSetup: true,
                    enableICloudAfterDismiss: !cloudSync.syncEnabled
                )
            }
        } message: {
            Text(restorePromptMessage)
        }
        .alert(String(localized: "Restaurar compras"), isPresented: $showRestoreFeedbackAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreFeedbackMessage)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        // Subtle adaptive gradient background. Hero/welcome step can opt into
        // its own full-screen background.
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
            WelcomeStepView(
                onContinue: advance,
                onRestore: restorePurchasesFromWelcome,
                isRestoring: subscriptionManager.isRestoring
            )
        case .overview:
            OverviewStepView(onContinue: advance)
        case .recipeIdeas:
            RecipeIdeasStepView(onContinue: advance)
        case .saveRecipes:
            SaveRecipesStepView(onContinue: advance)
        case .smartCount:
            SmartCountStepView(onContinue: advance)
        case .multimodalLogging:
            MultimodalLoggingStepView(onContinue: advance)
        case .pantryGrocerySync:
            PantryGrocerySyncStepView(onContinue: advance)
        case .nutritionCoach:
            NutritionCoachStepView(onContinue: advance)
        case .selectPantry:
            SelectPantryStepView(state: state, onContinue: advance)
        case .selectGrocery:
            SelectGroceryStepView(state: state, onContinue: advance)
        case .selectRecipes:
            SelectRecipesStepView(state: state, onContinue: advance)
        case .discoverySource:
            DiscoverySourceStepView(state: state, onContinue: advance)
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
                // Commit data while the animation plays out, then advance.
                commitOnboardingChoices(subscribed: false)
                advance()
            })
        case .goalProjection:
            GoalProjectionStepView(state: state, onContinue: advance)
        case .appReview:
            AppReviewStepView(state: state, onContinue: advance)
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

    /// Hide the progress bar on the very first hero/welcome step and on the
    /// final paywall step (which
    /// renders its own full-bleed chrome). Also hidden on the goal projection
    /// reveal so the result animation can take the whole screen.
    private var showsProgressBar: Bool {
        let step = OnboardingStep(rawValue: state.stepIndex) ?? .welcome
        return step != .welcome && step != .paywall && step != .goalProjection
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var restorePromptButtonTitle: String {
        cloudSync.syncEnabled
            ? String(localized: "Pular onboarding")
            : String(localized: "Configurar iCloud e pular")
    }

    private var restorePromptMessage: String {
        cloudSync.syncEnabled
            ? String(localized: "Sua assinatura Premium já está ativa. Você pode pular o restante do onboarding agora.")
            : String(localized: "Sua assinatura Premium já está ativa. Você pode configurar o iCloud agora e pular o restante do onboarding.")
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

    private func restorePurchasesFromWelcome() {
        guard !subscriptionManager.isRestoring else { return }

        Task { @MainActor in
            await subscriptionManager.restore()

            let message = subscriptionManager.lastRestoreMessage
                ?? String(localized: "Nenhuma compra anterior encontrada.")

            if subscriptionManager.isSubscribed {
                restorePromptTitle = message
                showRestorePrompt = true
            } else {
                restoreFeedbackMessage = message
                showRestoreFeedbackAlert = true
            }
        }
    }

    /// Commits everything to the database and dismisses the flow.
    /// Phase 0 ships with a no-op commit (the placeholder steps don't touch
    /// the DB yet); later phases will fill `commitOnboardingChoices` in.
    private func finishOnboarding(
        subscribed: Bool,
        skippingSetup: Bool = false,
        enableICloudAfterDismiss: Bool = false
    ) {
        if subscribed && state.selectedPlanID == nil {
            state.selectedPlanID = subscriptionManager.activeProductID
        }

        let submission = OnboardingSubmissionPayload(state: state, subscribed: subscribed)
        if skippingSetup {
            markSelectionlessOnboardingComplete()
        } else {
            commitOnboardingChoices(subscribed: subscribed)
        }
        if let discoverySourceID = state.discoverySourceID {
            UserDefaults.standard.set(discoverySourceID, forKey: "onboarding.discoverySourceID")
        }
        Task {
            await OnboardingSubmissionUploader.upload(submission)
        }
        markOnboardingComplete()
        onFinish()

        if enableICloudAfterDismiss && !cloudSync.syncEnabled {
            Task { @MainActor in
                do {
                    try await cloudSync.enableCloudSync()
                } catch {
                    cloudSync.syncError = error.localizedDescription
                }
            }
        }
    }

    private func markSelectionlessOnboardingComplete() {
        didCommitChoices = true
        NutritionProfileStore.markOnboardingComplete(in: modelContext)
    }

    private func commitOnboardingChoices(subscribed: Bool) {
        guard !didCommitChoices else { return }
        didCommitChoices = true

        // Re-running onboarding from Settings must never wipe or duplicate
        // the user's existing data. Update the singleton nutrition profile,
        // merge selected items into existing lists, and only insert recipe
        // templates that don't already exist by exact normalized name.
        let goal = WeightGoal(rawValue: state.nutritionGoalRaw ?? "") ?? .maintain
        let profile = NutritionProfileStore.fetchOrCreate(in: modelContext)
        profile.sex = NutritionSex(rawValue: state.nutritionSexRaw ?? "") ?? .other
        profile.birthday = state.nutritionBirthday
        profile.heightCm = state.nutritionHeightCm
        profile.weightKg = state.nutritionWeightKg
        profile.activityLevel = ActivityLevel(rawValue: state.nutritionActivityRaw ?? "") ?? .moderate
        profile.weightGoal = goal
        profile.weeklyChangeKg = state.nutritionWeeklyChangeKg * (goal == .lose ? -1 : 1)
        profile.hasCompletedOnboarding = true
        profile.updatedAt = .now

        var allItems = (try? modelContext.fetch(FetchDescriptor<UnifiedItem>())) ?? []
        var nextPantrySortOrder = (allItems.filter(\.isPantry).map(\.pantrySortOrder).max() ?? -1) + 1
        var nextGrocerySortOrder = (allItems.filter(\.isGrocery).map(\.grocerySortOrder).max() ?? -1) + 1
        let onboardingToday = Calendar.current.startOfDay(for: .now)
        let wasOnboardingAlreadyCompleted =
            ((try? modelContext.fetch(FetchDescriptor<AppSettings>()))?.first?.hasCompletedOnboarding == true)
        var selectedPantryItems: [UnifiedItem] = []

        // Merge pantry selections into existing items when possible.
        for (index, id) in state.selectedPantryItemIDs.enumerated() {
            guard let template = OnboardingCatalog.pantryItems.first(where: { $0.id == id }) else { continue }
            if let existingItem = UnifiedItem.mergedExistingItem(named: template.displayName, in: allItems, context: modelContext) {
                let wasPantry = existingItem.isPantry
                let templateItem = UnifiedItem(
                    name: template.displayName,
                    category: template.category,
                    iconName: template.iconFileName,
                    isPantry: true,
                    pantrySortOrder: wasPantry ? existingItem.pantrySortOrder : nextPantrySortOrder
                )
                existingItem.mergeDetails(from: templateItem)
                if !wasPantry {
                    nextPantrySortOrder += 1
                }
                selectedPantryItems.append(existingItem)
                continue
            }

            let item = UnifiedItem(
                name: template.displayName,
                category: template.category,
                iconName: template.iconFileName,
                isPantry: true,
                pantrySortOrder: max(index, nextPantrySortOrder)
            )
            nextPantrySortOrder = item.pantrySortOrder + 1
            modelContext.insert(item)
            allItems.append(item)
            selectedPantryItems.append(item)
        }

        if !selectedPantryItems.contains(where: { item in
            guard let expirationDate = item.expirationDate else { return false }
            return Calendar.current.isDate(expirationDate, inSameDayAs: onboardingToday)
        }), let itemToExpireToday = selectedPantryItems.first(where: { $0.expirationDate == nil })
            ?? (wasOnboardingAlreadyCompleted ? nil : selectedPantryItems.first) {
            itemToExpireToday.expirationDate = onboardingToday
        }

        // Merge grocery selections into existing items when possible.
        for (index, id) in state.selectedGroceryItemIDs.enumerated() {
            guard let template = OnboardingCatalog.groceryItems.first(where: { $0.id == id }) else { continue }
            if let existingItem = UnifiedItem.mergedExistingItem(named: template.displayName, in: allItems, context: modelContext) {
                let wasGrocery = existingItem.isGrocery
                let templateItem = UnifiedItem(
                    name: template.displayName,
                    category: template.category,
                    iconName: template.iconFileName,
                    isGrocery: true,
                    grocerySortOrder: wasGrocery ? existingItem.grocerySortOrder : nextGrocerySortOrder
                )
                existingItem.mergeDetails(from: templateItem)
                if !wasGrocery {
                    nextGrocerySortOrder += 1
                }
                continue
            }

            let item = UnifiedItem(
                name: template.displayName,
                category: template.category,
                iconName: template.iconFileName,
                isGrocery: true,
                grocerySortOrder: max(index, nextGrocerySortOrder)
            )
            nextGrocerySortOrder = item.grocerySortOrder + 1
            modelContext.insert(item)
            allItems.append(item)
        }

        var existingRecipes = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? []

        // Insert recipe templates only when they don't already exist.
        for id in state.selectedRecipeTemplateIDs {
            guard let template = OnboardingCatalog.recipeTemplates.first(where: { $0.id == id }) else { continue }
            guard !hasExistingRecipe(named: template.name, in: existingRecipes) else { continue }

            let coverImageData = template.photoFileName.flatMap(IconResolver.imageData(forFilename:))

            let recipe = Recipe(
                name: template.name,
                descriptionText: template.summary,
                imageData: coverImageData,
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

            existingRecipes.append(recipe)
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

    private func hasExistingRecipe(named name: String, in recipes: [Recipe]) -> Bool {
        let normalized = UnifiedItem.normalizedName(name)
        guard !normalized.isEmpty else { return false }
        return recipes.contains { UnifiedItem.normalizedName($0.name) == normalized }
    }
}

// MARK: - Remote onboarding capture

private struct OnboardingSubmissionPayload: Encodable {
    let submissionID: String
    let submittedAt: String
    let localeIdentifier: String
    let preferredLanguage: String
    let regionCode: String?
    let discoverySourceID: String?
    let discoverySourceTitle: String?
    let nutritionGoal: String?
    let nutritionSex: String?
    let nutritionActivity: String?
    let nutritionRateMode: String
    let ageYears: Int?
    let heightCm: Double
    let weightKg: Double
    let weeklyChangeKg: Double
    let targetWeightKg: Double
    let targetMonths: Int
    let selectedPlanID: String?
    let subscribed: Bool
    let pantryItemIDs: [String]
    let groceryItemIDs: [String]
    let recipeTemplateIDs: [String]
    let pantryItemNames: [String]
    let groceryItemNames: [String]
    let recipeTemplateNames: [String]

    init(state: OnboardingState, subscribed: Bool) {
        let locale = Locale.current
        let discovery = state.discoverySourceID.flatMap { DiscoverySourceOption(rawValue: $0) }

        submissionID = UUID().uuidString.lowercased()
        submittedAt = ISO8601DateFormatter().string(from: .now)
        localeIdentifier = locale.identifier
        preferredLanguage = Locale.preferredLanguages.first ?? locale.identifier
        regionCode = locale.region?.identifier
        discoverySourceID = state.discoverySourceID
        discoverySourceTitle = discovery?.title
        nutritionGoal = state.nutritionGoalRaw
        nutritionSex = state.nutritionSexRaw
        nutritionActivity = state.nutritionActivityRaw
        nutritionRateMode = state.nutritionRateMode.rawValue
        ageYears = Self.ageYears(from: state.nutritionBirthday)
        heightCm = state.nutritionHeightCm
        weightKg = state.nutritionWeightKg
        weeklyChangeKg = state.nutritionWeeklyChangeKg
        targetWeightKg = state.nutritionTargetWeightKg
        targetMonths = state.nutritionTargetMonths
        selectedPlanID = state.selectedPlanID
        self.subscribed = subscribed
        pantryItemIDs = state.selectedPantryItemIDs.sorted()
        groceryItemIDs = state.selectedGroceryItemIDs.sorted()
        recipeTemplateIDs = state.selectedRecipeTemplateIDs.sorted()
        pantryItemNames = Self.names(for: state.selectedPantryItemIDs, in: OnboardingCatalog.pantryItems)
        groceryItemNames = Self.names(for: state.selectedGroceryItemIDs, in: OnboardingCatalog.groceryItems)
        recipeTemplateNames = state.selectedRecipeTemplateIDs.sorted().compactMap { id in
            OnboardingCatalog.recipeTemplates.first(where: { $0.id == id })?.name
        }
    }

    private static func names(
        for ids: Set<String>,
        in templates: [OnboardingCatalog.ItemTemplate]
    ) -> [String] {
        ids.sorted().compactMap { id in
            templates.first(where: { $0.id == id })?.displayName
        }
    }

    private static func ageYears(from birthday: Date?) -> Int? {
        guard let birthday else { return nil }
        return Calendar.current.dateComponents([.year], from: birthday, to: .now).year
    }
}

@MainActor
private enum OnboardingSubmissionUploader {
    static func upload(_ submission: OnboardingSubmissionPayload) async {
        let client = SupabaseClient()
        guard client.isConfigured else { return }

        do {
            try await client.restPOST(table: "onboarding_submissions", body: submission)
        } catch {
            #if DEBUG
            print("Onboarding submission upload failed: \(error)")
            #endif
        }
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
        case .overview: return "Tudo num só lugar"
        case .recipeIdeas: return "Ideias para cozinhar"
        case .saveRecipes: return "Salve qualquer receita"
        case .smartCount: return "Contagem inteligente"
        case .multimodalLogging: return "Registre como quiser"
        case .pantryGrocerySync: return "Despensa ⇄ Mercado"
        case .nutritionCoach: return "Nutrition Coach"
        case .selectPantry: return "Escolha sua despensa inicial"
        case .selectGrocery: return "Sua primeira lista de compras"
        case .selectRecipes: return "O que você gosta de cozinhar?"
        case .goal: return "Qual o seu objetivo?"
        case .sex: return "Sobre você"
        case .birthday: return "Quando você nasceu?"
        case .body: return "Altura e peso"
        case .activity: return "Nível de atividade"
        case .rate: return "Ritmo da mudança"
        case .discoverySource: return "Como você conheceu o Savoria?"
        case .preparing: return "Preparando seu app…"
        case .goalProjection: return "Sua trajetória"
        case .appReview: return "Avaliação na App Store"
        case .paywall: return "Smart Kitchen Premium"
        }
    }

    private var stepSubtitle: String? {
        step == .welcome ? "Esta é uma visualização de desenvolvimento. As telas finais virão nas próximas fases." : nil
    }
}

// MARK: - Discovery source step

private struct AppReviewStepView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.requestReview) private var requestReview

    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    @State private var showContent = false
    @State private var showStars = false
    @State private var showFootnote = false
    @State private var promptTask: Task<Void, Never>? = nil

    private let chipTint = Color(red: 0.98, green: 0.66, blue: 0.22)
    private let starGradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.79, blue: 0.30),
            Color(red: 1.00, green: 0.61, blue: 0.33)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    // Small subview extracted to help the type checker with the gradient vs. color overloads
    private struct StarRow: View {
        let show: Bool
        let gradient: LinearGradient

        var body: some View {
            HStack(spacing: 7) {
                ForEach(0..<5, id: \.self) { index in
                    // Use AnyShapeStyle to erase the concrete style type (Color vs. LinearGradient)
                    let style: AnyShapeStyle = show ? AnyShapeStyle(gradient) : AnyShapeStyle(Color.secondary.opacity(0.22))
                    Image(systemName: "star.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(style)
                        .scaleEffect(show ? 1 : 0.6)
                        .opacity(show ? 1 : 0.15)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.72)
                                .delay(Double(index) * 0.05),
                            value: show
                        )
                }
            }
        }
    }

    private var appName: String {
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }

        return Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Savoria"
    }

    var body: some View {
        bodyContent
            .background(bodyBackground)
            .onAppear { startExperience() }
            .onDisappear {
                promptTask?.cancel()
                promptTask = nil
            }
    }

    private var bodyContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            OnboardingFeatureChip(
                icon: "star.fill",
                title: String(localized: "App Store"),
                tint: chipTint
            )
            .padding(.bottom, 18)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 8)
            .animation(.spring(response: 0.55, dampingFraction: 0.82), value: showContent)

            OnboardingHeader(
                title: String(localized: "Avaliar na App Store"),
                subtitle: String(localized: "Sua opinião ajuda outras pessoas a descobrirem o app.")
            )
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 10)
            .animation(.spring(response: 0.6, dampingFraction: 0.84), value: showContent)

            reviewCard
                .padding(.horizontal, 24)
                .padding(.top, 28)

            Text(String(localized: "Se o sistema permitir, o pedido aparece agora. Se não, você pode avaliar depois em Configurações."))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 18)
                .opacity(showFootnote ? 1 : 0)
                .offset(y: showFootnote ? 0 : 6)
                .animation(.easeOut(duration: 0.28), value: showFootnote)

            Spacer(minLength: 16)

            OnboardingPrimaryButton(
                title: String(localized: "Continuar"),
                isEnabled: true,
                action: onContinue
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var bodyBackground: some View {
#if os(macOS)
        AnyView(backgroundLayer.ignoresSafeArea())
#else
        backgroundLayer.ignoresSafeArea()
#endif
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.09, green: 0.08, blue: 0.07),
                    Color(red: 0.13, green: 0.11, blue: 0.15)
                ]
                : [
                    Color(red: 1.00, green: 0.98, blue: 0.95),
                    Color(red: 0.97, green: 0.95, blue: 1.00)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var reviewCard: some View {
        // Precompute styles to simplify nested ternaries for the type checker
        let cardFill: Color = colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white.opacity(0.88)
        let cardBorder: Color = colorScheme == .dark
            ? Color.white.opacity(0.08)
            : chipTint.opacity(0.18)

        return HStack(spacing: 16) {
            Image("AppLogoB")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(
                    color: colorScheme == .dark
                        ? Color.black.opacity(0.22)
                        : chipTint.opacity(0.18),
                    radius: 16,
                    y: 8
                )

            VStack(alignment: .leading, spacing: 8) {
                Text(appName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(String(localized: "Avaliar na App Store"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                StarRow(show: showStars, gradient: starGradient)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        )
        .shadow(
            color: colorScheme == .dark
                ? Color.black.opacity(0.18)
                : chipTint.opacity(0.12),
            radius: 24,
            y: 12
        )
        .opacity(showContent ? 1 : 0)
        .scaleEffect(showContent ? 1 : 0.94)
        .animation(.spring(response: 0.6, dampingFraction: 0.84), value: showContent)
    }

    private func startExperience() {
        promptTask?.cancel()

        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            showContent = true
        }

        promptTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.45, dampingFraction: 0.74)) {
                showStars = true
            }

            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.28)) {
                showFootnote = true
            }

            guard !state.didRequestAppStoreReview else { return }
            state.didRequestAppStoreReview = true

            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            requestReview()
        }
    }
}

private struct DiscoverySourceStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            OnboardingHeader(
                title: String(localized: "Como você conheceu o Savoria?"),
                subtitle: String(localized: "Isso nos ajuda a entender o que fez sentido pra você.")
            )
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(DiscoverySourceOption.allCases) { option in
                        OnboardingChoiceCard(
                            title: option.title,
                            subtitle: option.subtitle,
                            isSelected: state.discoverySourceID == option.id,
                            icon: {
                                Image(systemName: option.iconName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(option.tint)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        Circle().fill(option.tint.opacity(0.14))
                                    )
                            },
                            action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    state.discoverySourceID = option.id
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            VStack(spacing: 8) {
                Text(String(localized: "Você pode alterar isso depois nas configurações."))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                OnboardingPrimaryButton(
                    title: String(localized: "Continuar"),
                    isEnabled: state.canAdvanceDiscoverySource,
                    action: onContinue
                )
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
    }
}

private enum DiscoverySourceOption: String, CaseIterable, Identifiable {
    case tiktok
    case instagram
    case youtube
    case appStore
    case friend
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiktok:
            return String(localized: "TikTok")
        case .instagram:
            return String(localized: "Instagram")
        case .youtube:
            return String(localized: "YouTube")
        case .appStore:
            return String(localized: "App Store")
        case .friend:
            return String(localized: "Indicação")
        case .other:
            return String(localized: "Outro")
        }
    }

    var subtitle: String {
        switch self {
        case .tiktok:
            return String(localized: "Vi um vídeo curto mostrando o app.")
        case .instagram:
            return String(localized: "Vi um post, story ou reels.")
        case .youtube:
            return String(localized: "Vi um vídeo ou review mais completo.")
        case .appStore:
            return String(localized: "Encontrei pesquisando por apps.")
        case .friend:
            return String(localized: "Alguém me recomendou o Savoria.")
        case .other:
            return String(localized: "Cheguei por outro caminho.")
        }
    }

    var iconName: String {
        switch self {
        case .tiktok:
            return "music.note.tv"
        case .instagram:
            return "camera.aperture"
        case .youtube:
            return "play.rectangle.fill"
        case .appStore:
            return "magnifyingglass"
        case .friend:
            return "person.2.fill"
        case .other:
            return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .tiktok:
            return Color(red: 0.28, green: 0.81, blue: 0.73)
        case .instagram:
            return Color(red: 0.92, green: 0.39, blue: 0.62)
        case .youtube:
            return Color(red: 0.93, green: 0.27, blue: 0.25)
        case .appStore:
            return Color(red: 0.35, green: 0.58, blue: 0.98)
        case .friend:
            return Color(red: 0.98, green: 0.72, blue: 0.34)
        case .other:
            return Color(red: 0.57, green: 0.52, blue: 0.96)
        }
    }
}
