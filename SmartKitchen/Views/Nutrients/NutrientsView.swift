import SwiftUI
import SwiftData

/// Tela principal da aba Nutrição.
/// - Apresenta o dashboard diário dentro do `ExpandedPageLayout`
/// - Expõe o botão de progresso (chart) e o menu "+" na área de shader
/// - Apresenta o onboarding na primeira abertura
struct NutrientsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger

    @Query(sort: \NutritionProfile.createdAt, order: .forward) private var profiles: [NutritionProfile]
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var allEntries: [FoodEntry]

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var showOnboarding = false
    @State private var activeEntrySheet: NutritionEntrySheet?
    @State private var editingEntry: FoodEntry?
    @State private var pushProgress = false

    private var profile: NutritionProfile? { profiles.first }

    var body: some View {
        ExpandedPageLayout(
            pageTheme: .nutrients,
            header: { isInverted in
                PageHeader(title: "Nutrição", isInverted: isInverted) {
                    HStack(spacing: 6) {
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "chart.line.uptrend.xyaxis") {
                                pushProgress = true
                            }
                        }
                        GlassButtonGroup {
                            GlassGroupMenu(systemImage: "plus") {
                                Button {
                                    activeEntrySheet = .capturePhoto
                                } label: {
                                    Label("Foto da refeição", systemImage: "camera")
                                }
                                Button {
                                    activeEntrySheet = .captureLabel
                                } label: {
                                    Label("Rótulo nutricional", systemImage: "barcode.viewfinder")
                                }
                                Button {
                                    activeEntrySheet = .captureVoice
                                } label: {
                                    Label("Por voz", systemImage: "mic")
                                }
                                Button {
                                    activeEntrySheet = .captureText
                                } label: {
                                    Label("Por texto", systemImage: "text.cursor")
                                }
                                Divider()
                                Button {
                                    activeEntrySheet = .manual
                                } label: {
                                    Label("Entrada manual", systemImage: "square.and.pencil")
                                }
                                Button {
                                    activeEntrySheet = .recents
                                } label: {
                                    Label("Recentes", systemImage: "clock.arrow.circlepath")
                                }
                            }
                        }
                        SettingsButton()
                    }
                }
            },
            content: {
                if let profile, profile.hasCompletedOnboarding {
                    NutritionDashboardView(
                        profile: profile,
                        allEntries: allEntries,
                        selectedDate: $selectedDate,
                        onTapEntry: { entry in
                            editingEntry = entry
                        },
                        onDeleteEntry: delete
                    )
                } else {
                    emptyState
                }
            },
            infoContent: {
                NutrientsInfoContent(
                    profile: profile,
                    caloriesToday: caloriesToday
                )
            }
        )
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .tint(PageTheme.nutrients.accentColor)
        .onAppear { presentOnboardingIfNeeded() }
        .onChange(of: profiles.count) { _, _ in presentOnboardingIfNeeded() }
        .onChange(of: scrollToTopTrigger) { _, _ in
            selectedDate = Calendar.current.startOfDay(for: .now)
        }
        .sheet(isPresented: $showOnboarding) {
            NutritionOnboardingView()
                .interactiveDismissDisabled()
        }
        .sheet(item: $activeEntrySheet) { sheet in
            sheetContent(for: sheet)
        }
        .sheet(item: $editingEntry) { entry in
            FoodEntryFormView(mode: .edit(entry: entry))
        }
        .navigationDestination(isPresented: $pushProgress) {
            NutritionProgressView()
        }
    }

    // MARK: - Computed

    private var caloriesToday: Int {
        let today = Calendar.current.startOfDay(for: .now)
        return allEntries
            .filter { Calendar.current.isDate($0.timestamp, inSameDayAs: today) }
            .reduce(0) { $0 + $1.calories }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(PageTheme.nutrients.gradient)
            Text("Configure seu perfil")
                .font(.sectionTitle)
            Text("Responda 6 perguntas rápidas para calcularmos suas metas diárias de calorias e macros.")
                .font(.serifBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showOnboarding = true
            } label: {
                Text("Começar")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(PageTheme.nutrients.gradient, in: .capsule)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sheet routing

    @ViewBuilder
    private func sheetContent(for sheet: NutritionEntrySheet) -> some View {
        switch sheet {
        case .manual:
            FoodEntryFormView(mode: .create(onDate: selectedDate))
        case .recents:
            RecentsView(logDate: selectedDate)
        case .capturePhoto:
            FoodCaptureHostView(mode: .photo, logDate: selectedDate)
        case .captureLabel:
            FoodCaptureHostView(mode: .nutritionLabel, logDate: selectedDate)
        case .captureText:
            FoodCaptureHostView(mode: .text, logDate: selectedDate)
        case .captureVoice:
            FoodCaptureHostView(mode: .voice, logDate: selectedDate)
        case .comingSoon(let title):
            comingSoonSheet(title: title)
        }
    }

    private func comingSoonSheet(title: String) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "hourglass")
                    .font(.system(size: 48))
                    .foregroundStyle(PageTheme.nutrients.accentColor)
                Text(title)
                    .font(.sectionTitle)
                Text("Disponível em breve.")
                    .font(.serifBody)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modalNavigationTitle(title)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Mutations

    private func presentOnboardingIfNeeded() {
        if profile == nil || profile?.hasCompletedOnboarding == false {
            // Permite ao usuário fechar e reabrir via emptyState.
            if profile == nil {
                _ = NutritionProfileStore.fetchOrCreate(in: modelContext)
            }
            showOnboarding = true
        }
    }

    private func delete(_ entry: FoodEntry) {
        if let filename = entry.imageFilename {
            FoodImageStore.shared.delete(filename: filename)
        }
        modelContext.delete(entry)
        try? modelContext.save()
    }
}
