import SwiftUI
import SwiftData

/// Tela principal da aba Nutrição.
/// - Apresenta o dashboard diário dentro do `ExpandedPageLayout`
/// - Expõe o botão de progresso (chart) e o menu "+" na área de detalhe do cabeçalho
/// - Apresenta o onboarding na primeira abertura
struct NutrientsView: View {
    var body: some View {
        #if os(iOS)
        DeferredTabPage(tab: .nutrients) {
            NutrientsLoadedView()
        } placeholder: {
            NutrientsSkeletonPage()
        }
        #else
        NutrientsLoadedView()
        #endif
    }
}

#if os(iOS)
private struct NutrientsSkeletonPage: View {
    var body: some View {
        ExpandedPageLayout(
            pageTheme: .nutrients,
            header: { isInverted in
                PageHeader(title: String(localized: "Nutrição"), isInverted: isInverted) {
                    HStack(spacing: 6) {
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "plus") {}
                        }
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "chart.line.uptrend.xyaxis") {}
                        }
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "scalemass") {}
                        }
                        SettingsButton()
                    }
                    .disabled(true)
                }
            },
            content: {
                AppLaunchSkeletonPage(kind: .nutrition, presentation: .contentOnly)
            },
            infoContent: {
                NutritionInfoSkeleton()
            }
        )
        .toolbar(.hidden, for: .navigationBar)
    }
}
#endif

private struct NutrientsLoadedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger

    @Query(sort: \NutritionProfile.createdAt, order: .forward) private var profiles: [NutritionProfile]
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var allEntries: [FoodEntry]
    @Query(sort: \NutritionDayLog.dayStart, order: .reverse) private var allDayLogs: [NutritionDayLog]

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var showOnboarding = false
    @State private var activeEntrySheet: NutritionEntrySheet?
    @State private var editingEntry: FoodEntry?
    @State private var pushProgress = false
    @State private var pushWeightTracker = false

    private var profile: NutritionProfile? { profiles.first }

    private var fullscreenEntrySheetBinding: Binding<NutritionEntrySheet?> {
        Binding(
            get: {
                guard let sheet = activeEntrySheet,
                      sheet.prefersFullScreenPresentation else {
                    return nil
                }

                return sheet
            },
            set: { activeEntrySheet = $0 }
        )
    }

    private var sheetEntrySheetBinding: Binding<NutritionEntrySheet?> {
        Binding(
            get: {
                guard let sheet = activeEntrySheet,
                      !sheet.prefersFullScreenPresentation else {
                    return nil
                }

                return sheet
            },
            set: { activeEntrySheet = $0 }
        )
    }

    var body: some View {
        ExpandedPageLayout(
            pageTheme: .nutrients,
            header: { isInverted in
                PageHeader(title: String(localized: "Nutrição"), isInverted: isInverted) {
                    HStack(spacing: 6) {
                        GlassButtonGroup {
                            GlassGroupMenu(systemImage: "plus") {
                                Section("Registros Salvos") {
                                    Button {
                                        activeEntrySheet = .manual()
                                    } label: {
                                        Label("Salvar alimento", systemImage: "fork.knife")
                                    }
                                    Button {
                                        activeEntrySheet = .recents
                                    } label: {
                                        Label("Alimentos salvos", systemImage: "clock.arrow.circlepath")
                                    }
                                }
                                Section("Registros Manuais") {
                                    Button {
                                        activeEntrySheet = .manual()
                                    } label: {
                                        Label("Registrar manualmente", systemImage: "square.and.pencil")
                                    }
                                }
                                Section("Registrar por…") {
                                    Button {
                                        activeEntrySheet = .captureLabel
                                    } label: {
                                        Label("Rótulo", systemImage: "doc.text.viewfinder")
                                    }
                                    Button {
                                        activeEntrySheet = .capturePhotoGallery
                                    } label: {
                                        Label("Galeria", systemImage: "photo")
                                    }
                                    #if os(iOS)
                                    Button {
                                        activeEntrySheet = .capturePhotoCamera
                                    } label: {
                                        Label("Câmera", systemImage: "camera")
                                    }
                                    #endif
                                    Button {
                                        activeEntrySheet = .captureVoice
                                    } label: {
                                        Label("Voz", systemImage: "waveform")
                                    }
                                    Button {
                                        activeEntrySheet = .captureText(prefillText: nil, autoAnalyze: false)
                                    } label: {
                                        Label("Texto", systemImage: "character.cursor.ibeam")
                                    }
                                }
                            }
                        }
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "chart.line.uptrend.xyaxis") {
                                pushProgress = true
                            }
                        }
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "scalemass") {
                                pushWeightTracker = true
                            }
                        }
                        #if !os(macOS)
                        SettingsButton()
                        #endif
                    }
                }
            },
            content: {
                if let profile, profile.hasCompletedOnboarding {
                    NutritionDashboardView(
                        profile: profile,
                        allEntries: allEntries,
                        allDayLogs: allDayLogs,
                        selectedDate: $selectedDate,
                        onTapEntry: { entry in
                            editingEntry = entry
                        },
                        onDeleteEntry: delete,
                        onPickEntry: { sheet in
                            activeEntrySheet = sheet
                        },
                        onOpenProgress: { pushProgress = true }
                    )
                } else {
                    emptyState
                }
            },
            infoContent: {
                NutrientsInfoContent(
                    profile: profile,
                    selectedDate: selectedDate,
                    selectedDayState: selectedDayState,
                    caloriesConsumed: caloriesForSelectedDate,
                    onTapScore: { pushProgress = true }
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
        .onReceive(NotificationCenter.default.publisher(for: .openNutritionAtDate)) { note in
            if let date = note.userInfo?["date"] as? Date {
                selectedDate = Calendar.current.startOfDay(for: date)
            }
        }
        .sheet(isPresented: $showOnboarding) {
            NutritionOnboardingHostView()
        }
        #if os(iOS)
        .fullScreenCover(item: fullscreenEntrySheetBinding) { sheet in
            sheetContent(for: sheet)
        }
        .sheet(item: sheetEntrySheetBinding) { sheet in
            sheetContent(for: sheet)
        }
        #else
        .sheet(item: $activeEntrySheet) { sheet in
            sheetContent(for: sheet)
        }
        #endif
        .sheet(item: $editingEntry) { entry in
            FoodEntryFormView(mode: .edit(entry: entry))
        }
        .navigationDestination(isPresented: $pushProgress) {
            NutritionProgressView()
        }
        .navigationDestination(isPresented: $pushWeightTracker) {
            WeightTrackerView()
        }
    }

    // MARK: - Computed

    private var caloriesToday: Int {
        let today = Calendar.current.startOfDay(for: .now)
        return allEntries
            .filter { Calendar.current.isDate($0.timestamp, inSameDayAs: today) }
            .reduce(0) { $0 + $1.calories }
    }

    private var caloriesForSelectedDate: Int {
        allEntries
            .filter { Calendar.current.isDate($0.timestamp, inSameDayAs: selectedDate) }
            .reduce(0) { $0 + $1.calories }
    }

    private var selectedDayState: NutritionDayState {
        NutritionDayLogStore.state(
            for: selectedDate,
            entries: allEntries,
            logs: allDayLogs,
            calendar: .current
        )
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
        case .manual(let prefillName, let prefillMealType):
            FoodEntryFormView(
                mode: .create(onDate: selectedDate),
                prefillName: prefillName,
                prefillMealType: prefillMealType
            )
        case .recents:
            RecentsView(logDate: selectedDate)
        case .capturePhotoCamera:
            FoodCaptureHostView(mode: .photo, logDate: selectedDate, initialInput: .camera)
        case .capturePhotoGallery:
            FoodCaptureHostView(mode: .photo, logDate: selectedDate, initialInput: .gallery)
        case .captureLabel:
            FoodCaptureHostView(mode: .nutritionLabel, logDate: selectedDate)
        case .captureText(let prefillText, let autoAnalyze):
            FoodCaptureHostView(
                mode: .text,
                logDate: selectedDate,
                initialText: prefillText ?? "",
                shouldAutoAnalyzeTextOnAppear: autoAnalyze
            )
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
