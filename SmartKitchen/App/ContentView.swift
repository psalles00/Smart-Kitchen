import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsArray: [AppSettings]
    @State private var selectedTab: AppTab = .assistant
    @State private var lastContentTab: AppTab = .assistant
    @State private var showAddOptions = false
    @State private var addSheetType: AddSheetType?
    @State private var showAssistant = false
    @State private var showSettings = false

    private var settings: AppSettings? { settingsArray.first }
    private var addMenuOptions: [AddSheetType] {
        [.pantryItem, .groceryItem, .recipe, .assistantConversation]
    }
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == .add {
                    openAddOptionsFromTab()
                    return
                }

                selectedTab = newValue
                lastContentTab = newValue
                if showAddOptions {
                    closeAddMenu()
                }
            }
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            mainTabView

            if showAddOptions {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeAddMenu()
                    }
                    .transition(.opacity)
            }

            addOptionsOverlay
        }
        .sheet(item: $addSheetType) { type in
            NavigationStack {
                switch type {
                case .pantryItem:
                    AddPantryItemView()
                case .groceryItem:
                    AddGroceryItemView()
                case .recipe:
                    AddRecipeView()
                case .assistantConversation:
                    Color.clear
                }
            }
        }
        .preferredColorScheme(settings?.appearanceMode.colorScheme)
        .tint(settings?.accentColorChoice.color)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .sheet(isPresented: $showAssistant) {
            NavigationStack {
                AssistantView()
            }
        }
    }

    private var mainTabView: some View {
        Group {
            if #available(iOS 26, *) {
                TabView(selection: tabSelection) {
                    Tab(value: AppTab.assistant) {
                        NavigationStack {
                            HomeView()
                        }
                    } label: {
                        Label("Início", systemImage: AppTab.assistant.icon)
                    }

                    Tab(value: AppTab.lists) {
                        NavigationStack {
                            ListsTabView()
                        }
                    } label: {
                        Label("Listas", systemImage: AppTab.lists.icon)
                    }

                    Tab(value: AppTab.recipes) {
                        NavigationStack {
                            RecipesView()
                        }
                    } label: {
                        Label("Receitas", systemImage: AppTab.recipes.icon)
                    }

                    Tab(value: AppTab.nutrients) {
                        NavigationStack {
                            NutrientsPlaceholderView()
                        }
                    } label: {
                        Label("Nutrientes", systemImage: AppTab.nutrients.icon)
                    }

                    Tab(value: AppTab.add, role: .search) {
                        Color.clear
                    } label: {
                        Label("Adicionar", systemImage: AppTab.add.icon)
                    }
                }
            } else {
                TabView(selection: tabSelection) {
                    NavigationStack {
                        HomeView()
                    }
                    .tabItem {
                        Label("Início", systemImage: AppTab.assistant.icon)
                    }
                    .tag(AppTab.assistant)

                    NavigationStack {
                        ListsTabView()
                    }
                    .tabItem {
                        Label("Listas", systemImage: AppTab.lists.icon)
                    }
                    .tag(AppTab.lists)

                    NavigationStack {
                        RecipesView()
                    }
                    .tabItem {
                        Label("Receitas", systemImage: AppTab.recipes.icon)
                    }
                    .tag(AppTab.recipes)

                    NavigationStack {
                        NutrientsPlaceholderView()
                    }
                    .tabItem {
                        Label("Nutrientes", systemImage: AppTab.nutrients.icon)
                    }
                    .tag(AppTab.nutrients)

                    Color.clear
                        .tabItem {
                            Label("Adicionar", systemImage: AppTab.add.icon)
                        }
                        .tag(AppTab.add)
                }
            }
        }
    }

    private func selectAddType(_ type: AddSheetType) {
        closeAddMenu()
        switch type {
        case .assistantConversation:
            clearChatMessages()
            showAssistant = true
        case .recipe, .pantryItem, .groceryItem:
            addSheetType = type
        }
    }

    private func closeAddMenu() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            showAddOptions = false
        }
    }

    private func openAddOptionsFromTab() {
        selectedTab = lastContentTab
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            showAddOptions.toggle()
        }
    }

    private func clearChatMessages() {
        let descriptor = FetchDescriptor<ChatMessage>()
        let messages = (try? modelContext.fetch(descriptor)) ?? []
        for message in messages {
            modelContext.delete(message)
        }
    }

    private var addOptionsOverlay: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if showAddOptions {
                ForEach(Array(addMenuOptions.enumerated()), id: \.element.id) { index, type in
                    AddOptionButton(type: type) {
                        selectAddType(type)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .offset(x: 18, y: CGFloat(18 + (index * 10)))
                                .combined(with: .scale(scale: 0.92, anchor: .bottomTrailing))
                                .combined(with: .opacity),
                            removal: .offset(x: 10, y: 8)
                                .combined(with: .scale(scale: 0.96, anchor: .bottomTrailing))
                                .combined(with: .opacity)
                        )
                    )
                }
            }
        }
        .padding(.trailing, 14)
        .padding(.bottom, 88)
    }
}

private struct HomeView: View {
    @Query(sort: \PantryItem.name) private var pantryItems: [PantryItem]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var settingsArray: [AppSettings]

    @State private var showAssistant = false
    @State private var showAddGrocery = false
    @State private var showAddPantry = false
    @State private var selectedCompatibleCategory: String? = nil

    private var settings: AppSettings? { settingsArray.first }

    private var recipeCategories: [Category] {
        categories.filter { $0.type == .recipe }
    }

    private var compatibleMatches: [HomeRecipeMatch] {
        let pantryNames = pantryItems.map { normalized($0.name) }

        return recipes
            .filter { recipe in
                guard let selectedCompatibleCategory else { return true }
                return recipe.category == selectedCompatibleCategory
            }
            .compactMap { recipe -> HomeRecipeMatch? in
                guard let compatibility = recipe.compatibility(against: pantryNames) else { return nil }
                return HomeRecipeMatch(recipe: recipe, compatibilityInfo: compatibility)
            }
            .sorted {
                if $0.compatibility != $1.compatibility { return $0.compatibility > $1.compatibility }
                if $0.compatibilityInfo.matchedIngredients != $1.compatibilityInfo.matchedIngredients {
                    return $0.compatibilityInfo.matchedIngredients > $1.compatibilityInfo.matchedIngredients
                }
                if $0.recipe.isFavorite != $1.recipe.isFavorite { return $0.recipe.isFavorite && !$1.recipe.isFavorite }
                return $0.recipe.name.localizedCaseInsensitiveCompare($1.recipe.name) == .orderedAscending
            }
    }

    private var expiringItems: [PantryItem] {
        let leadDays = settings?.expiringItemsLeadDays ?? 30
        let now = Calendar.current.startOfDay(for: .now)
        let limit = Calendar.current.date(byAdding: .day, value: leadDays, to: now) ?? now

        return pantryItems
            .filter {
                guard let expirationDate = $0.expirationDate else { return false }
                let day = Calendar.current.startOfDay(for: expirationDate)
                return day >= now && day <= limit
            }
            .sorted {
                guard let lhs = $0.expirationDate, let rhs = $1.expirationDate else { return false }
                return lhs < rhs
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                assistantLauncher
                actionDeck
                if !expiringItems.isEmpty {
                    expiringSection
                }
                dessertShelf
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .navigationTitle("Início")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsButton()
            }
        }
        .sheet(isPresented: $showAssistant) {
            NavigationStack {
                AssistantView()
            }
        }
        .sheet(isPresented: $showAddGrocery) {
            NavigationStack {
                AddGroceryItemView()
            }
        }
        .sheet(isPresented: $showAddPantry) {
            NavigationStack {
                AddPantryItemView()
            }
        }
    }

    private var assistantLauncher: some View {
        Button {
            showAssistant = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Seu centro de cozinha")
                            .font(.sectionTitle)
                            .foregroundStyle(.primary)

                        Text("Abra o assistente em modal, acesse listas rápido e veja combinações da despensa sem depender de IA.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "sparkles.bubble")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 46, height: 46)
                        .background(Color.accentColor.opacity(0.14), in: .circle)
                }

                HStack(spacing: 8) {
                    compactPill("Abrir assistente", systemImage: "bubble.left.and.text.bubble.right.fill")
                    compactPill("Chat em modal", systemImage: "uiwindow.split.2x1")
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.16), Color.orange.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: 24)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var actionDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Atalhos")
                .font(.headline.weight(.semibold))

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                homeActionTile(
                    title: "Assistente",
                    subtitle: "Abrir chat",
                    systemImage: "sparkles",
                    tint: .blue
                ) {
                    showAssistant = true
                }

                homeActionTile(
                    title: "Mercado",
                    subtitle: "Adicionar item",
                    systemImage: "cart.badge.plus",
                    tint: .green
                ) {
                    showAddGrocery = true
                }

                homeActionTile(
                    title: "Despensa",
                    subtitle: "Modificar itens",
                    systemImage: "square.and.pencil",
                    tint: .orange
                ) {
                    showAddPantry = true
                }

                NavigationLink {
                    ListsTabView(initialSubtab: .pantry)
                } label: {
                    homeActionTileBody(
                        title: "Listas",
                        subtitle: "Abrir despensa",
                        systemImage: "list.bullet.clipboard",
                        tint: .indigo
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var expiringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Validades próximas")
                        .font(.headline.weight(.semibold))
                    Text("Itens da despensa que vencem em breve")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(expiringItems.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.14), in: .capsule)
            }

            VStack(spacing: 10) {
                ForEach(expiringItems.prefix(5)) { item in
                    HStack(spacing: 12) {
                        IconImage(name: item.name, fallbackSymbol: "clock.badge.exclamationmark", size: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                            if let expiration = item.formattedExpirationDate {
                                Text("Validade \(expiration)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let expirationDate = item.expirationDate {
                            Text(relativeExpirationText(for: expirationDate))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
                }
            }
        }
    }

    private var dessertShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receitas compatíveis")
                        .font(.headline.weight(.semibold))
                    Text("Ordenadas por compatibilidade com a sua despensa")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !compatibleMatches.isEmpty {
                    Text("\(compatibleMatches.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: .capsule)
                }
            }

            compatibleCategoryFilter

            if compatibleMatches.isEmpty {
                ContentUnavailableView(
                    "Sem receitas compatíveis",
                    systemImage: "fork.knife",
                    description: Text("Ajuste o grupo de receitas ou atualize a despensa para ver combinações aqui.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(compatibleMatches.prefix(8)) { match in
                            NavigationLink {
                                RecipeDetailView(recipe: match.recipe)
                            } label: {
                                HomeRecipeMatchCard(match: match)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var compatibleCategoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "Todos", isSelected: selectedCompatibleCategory == nil) {
                    selectedCompatibleCategory = nil
                }

                ForEach(recipeCategories) { category in
                    filterChip(label: category.name, isSelected: selectedCompatibleCategory == category.name) {
                        selectedCompatibleCategory = category.name
                    }
                }
            }
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Color.accentColor.opacity(0.16) : Color(.tertiarySystemBackground),
                    in: .capsule
                )
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    private func compactPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: .capsule)
    }

    private func homeActionTile(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            homeActionTileBody(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: tint
            )
        }
        .buttonStyle(.plain)
    }

    private func homeActionTileBody(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
    }

    private func normalized(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func relativeExpirationText(for date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        if days <= 0 { return "Hoje" }
        if days == 1 { return "1 dia" }
        return "\(days) dias"
    }
}

private struct HomeRecipeMatch: Identifiable {
    let recipe: Recipe
    let compatibilityInfo: RecipeCompatibility

    var id: UUID { recipe.id }
    var compatibility: Double { compatibilityInfo.ratio }
    var compactCompatibilityText: String { compatibilityInfo.compactText }
}

private struct HomeRecipeMatchCard: View {
    let match: HomeRecipeMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                recipeImage
                    .frame(width: 210, height: 118)
                    .clipShape(.rect(cornerRadius: 16))

                Text(match.compactCompatibilityText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.72), in: .capsule)
                    .padding(10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(match.recipe.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if match.recipe.totalTime > 0 {
                        Label("\(match.recipe.totalTime) min", systemImage: "clock")
                    }
                    Label(match.recipe.difficulty.rawValue, systemImage: match.recipe.difficulty.icon)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(match.compatibilityInfo.longText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 210, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var recipeImage: some View {
        if let data = match.recipe.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(.tertiarySystemFill), Color(.secondarySystemFill)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "birthday.cake")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.quaternary)
            }
        }
    }
}

// MARK: - Add Sheet Types

enum AddSheetType: String, Identifiable, CaseIterable {
    case recipe
    case pantryItem
    case groceryItem
    case assistantConversation

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .recipe:      "Nova Receita"
        case .pantryItem:  "Item da Despensa"
        case .groceryItem: "Item do Mercado"
        case .assistantConversation: "Nova Conversa"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .recipe:      "Crie e salve uma receita"
        case .pantryItem:  "Adicione algo que você já tem"
        case .groceryItem: "Inclua algo para comprar"
        case .assistantConversation: "Comece um novo chat com o assistente"
        }
    }

    var icon: String {
        switch self {
        case .recipe:      "book.badge.plus"
        case .pantryItem:  "refrigerator"
        case .groceryItem: "cart.badge.plus"
        case .assistantConversation: "square.and.pencil"
        }
    }
}

private struct AddOptionButton: View {
    let type: AddSheetType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(type.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: type.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }
}
