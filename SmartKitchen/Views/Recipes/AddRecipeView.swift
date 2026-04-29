import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct AddRecipeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query private var settingsArray: [AppSettings]
    @FocusState private var isNameFieldFocused: Bool

    // Basic info
    @State private var name = ""
    @State private var descriptionText = ""
    @State private var selectedCategories: [String] = []
    @State private var difficulty: Difficulty = .easy
    @State private var prepTime = 0
    @State private var cookTime = 0
    @State private var servings = 1
    @State private var calories: String = ""
    @State private var externalURLString = ""

    // Image
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showPhotoOptions = false
    @State private var showPhotoLibrary = false
    @State private var showCameraPicker = false
    @State private var showPhotoFileImporter = false
    @State private var showCameraUnavailableAlert = false
    @State private var showCategoryManager = false
    @State private var selectedPreparationItems: [PhotosPickerItem] = []
    @State private var preparationMedia: [DraftPreparationMedia] = []
    @State private var showPreparationMediaOptions = false
    @State private var showPreparationPhotoLibrary = false
    @State private var showPreparationCameraPicker = false
    @State private var showPreparationFileImporter = false

    // Dynamic ingredients
    @State private var ingredientItems: [RecipeIngredientEditorItem] = [.ingredient()]
    @State private var activeIngredientPicker: IngredientPickerTarget?

    // Dynamic steps
    @State private var stepRows: [StepRow] = [StepRow(order: 1)]

    // Dynamic utensils
    @State private var utensilNames: [IdentifiedUtensil] = []
    @State private var activeUtensilPicker: RecipeUtensilPickerTarget?

    private var settings: AppSettings? { settingsArray.first }

    private var recipeCategories: [Category] {
        allCategories.filter { $0.type == .recipe }
    }

    private var recipeCategorySignature: String {
        recipeCategories.map(\.name).joined(separator: "|")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        editorScaffold
            .formStyle(.grouped)
            #if os(macOS)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .frame(minWidth: 700, minHeight: 800)
            #endif
    }

    private var editorScaffold: some View {
        recipeForm
            .modalNavigationTitle(String(localized: "Nova Receita"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .tint(PageTheme.recipes.accentColor)
            .toolbar { toolbarContent }
            .onChange(of: selectedPhoto) {
                loadPhoto()
            }
            .onChange(of: selectedPreparationItems) {
                loadPreparationMedia()
            }
            .onAppear {
                DispatchQueue.main.async {
                    isNameFieldFocused = true
                }
                normalizeSelectedCategoriesIfNeeded()
            }
            .onChange(of: recipeCategorySignature) { _, _ in
                normalizeSelectedCategoriesIfNeeded()
            }
            .confirmationDialog("Adicionar Foto", isPresented: $showPhotoOptions, titleVisibility: .visible) {
                coverPhotoDialogContent
            }
            .photosPicker(isPresented: $showPhotoLibrary, selection: $selectedPhoto, matching: .images)
            .fileImporter(
                isPresented: $showPhotoFileImporter,
                allowedContentTypes: [.image]
            ) { result in
                handleCoverFileImport(result)
            }
            .sheet(isPresented: $showCameraPicker) {
                coverCameraSheet
                    .forceLightStatusBar()
            }
            .sheet(item: $activeIngredientPicker) { target in
                ItemIconPickerView(
                    initialQuery: ingredientName(for: target.id),
                    currentIconFileName: ingredientIconName(for: target.id),
                    fallbackSymbol: "leaf"
                ) { entry in
                    applyIngredientIcon(entry, to: target.id)
                }
                .forceLightStatusBar()
            }
            .sheet(item: $activeUtensilPicker) { target in
                ItemIconPickerView(
                    initialQuery: utensilName(for: target.id),
                    currentIconFileName: utensilIconName(for: target.id),
                    fallbackSymbol: "fork.knife"
                ) { entry in
                    applyUtensilIcon(entry, to: target.id)
                }
                .forceLightStatusBar()
            }
            .sheet(isPresented: $showPreparationCameraPicker) {
                preparationCameraSheet
                    .forceLightStatusBar()
            }
            .photosPicker(
                isPresented: $showPreparationPhotoLibrary,
                selection: $selectedPreparationItems,
                maxSelectionCount: 12,
                matching: .any(of: [.images, .videos])
            )
            .fileImporter(
                isPresented: $showPreparationFileImporter,
                allowedContentTypes: [.image, .movie],
                allowsMultipleSelection: true
            ) { result in
                handlePreparationFileImport(result)
            }
            .alert("Câmera indisponível", isPresented: $showCameraUnavailableAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Este dispositivo não permite capturar fotos no momento.")
            }
            .confirmationDialog("Adicionar Mídia", isPresented: $showPreparationMediaOptions, titleVisibility: .visible) {
                preparationMediaDialogContent
            }
    }

    private var recipeForm: some View {
        Form {
            imageSection
            basicInfoSection
            detailsSection
            preparationMediaSection
            ingredientsSection
            if settings?.showUtensils == true {
                RecipeUtensilsEditor(
                    utensilNames: $utensilNames,
                    onIconTapped: { activeUtensilPicker = RecipeUtensilPickerTarget(id: $0) }
                )
            }
            stepsSection
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancelar") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Salvar") { save() }
                .fontWeight(.semibold)
                .disabled(!isValid)
        }
    }

    @ViewBuilder
    private var coverCameraSheet: some View {
        #if os(iOS)
        CameraMediaPicker(mode: .photoOnly) { media in
            imageData = media.data
        }
        #else
        MacCameraMediaPicker(mode: .photoOnly) { media in
            imageData = media.data
        }
        .frame(minWidth: 640, minHeight: 520)
        #endif
    }

    @ViewBuilder
    private var preparationCameraSheet: some View {
        #if os(iOS)
        CameraMediaPicker(mode: .photoOrVideo) { media in
            preparationMedia.append(
                DraftPreparationMedia(
                    type: media.type,
                    data: media.data,
                    fileExtension: media.fileExtension
                )
            )
        }
        #else
        MacCameraMediaPicker(mode: .photoOnly) { media in
            preparationMedia.append(
                DraftPreparationMedia(
                    type: media.type,
                    data: media.data,
                    fileExtension: media.fileExtension
                )
            )
        }
        .frame(minWidth: 640, minHeight: 520)
        #endif
    }

    @ViewBuilder
    private var coverPhotoDialogContent: some View {
        Button("Tirar Foto") {
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                showCameraPicker = true
            } else {
                showCameraUnavailableAlert = true
            }
            #else
            showCameraPicker = true
            #endif
        }

        Button("Selecionar da Galeria") {
            showPhotoLibrary = true
        }

        Button("Selecionar dos Arquivos") {
            #if os(macOS)
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            if panel.runModal() == .OK, let url = panel.url,
               let data = try? Data(contentsOf: url) {
                imageData = data
            }
            #else
            showPhotoFileImporter = true
            #endif
        }

        Button("Colar da Área de Transferência") {
            pasteImageFromClipboard { data in
                if let data { imageData = data }
            }
        }

        if imageData != nil {
            Button("Remover Foto", role: .destructive) {
                imageData = nil
                selectedPhoto = nil
            }
        }
    }

    @ViewBuilder
    private var preparationMediaDialogContent: some View {
        Button("Tirar Foto ou Vídeo") {
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                showPreparationCameraPicker = true
            } else {
                showCameraUnavailableAlert = true
            }
            #else
            showPreparationCameraPicker = true
            #endif
        }

        Button("Selecionar da Galeria") {
            showPreparationPhotoLibrary = true
        }

        Button("Selecionar dos Arquivos") {
            #if os(macOS)
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image, .movie]
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            if panel.runModal() == .OK {
                for url in panel.urls {
                    if let data = try? Data(contentsOf: url) {
                        let media = pickedRecipeMedia(from: data, contentType: nil)
                        preparationMedia.append(DraftPreparationMedia(type: media.type, data: media.data, fileExtension: media.fileExtension))
                    }
                }
            }
            #else
            showPreparationFileImporter = true
            #endif
        }
    }

    // MARK: - Image

    private var imageSection: some View {
        Section {
            Button {
                showPhotoOptions = true
            } label: {
                ZStack(alignment: .bottomLeading) {
                    if let imageData, let image = PlatformImage(data: imageData) {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 18))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 120)
                            .overlay {
                                VStack(spacing: 10) {
                                    Image(systemName: "camera.aperture")
                                        .font(.title2)
                                        .foregroundStyle(Color.accentColor)

                                    Text("Adicionar Foto")
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Text("Câmera, galeria ou arquivos")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                            }
                    }

                    if imageData != nil {
                        Label("Alterar Foto", systemImage: "camera.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.55), in: .capsule)
                            .padding(14)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    // MARK: - Basic Info

    private var basicInfoSection: some View {
        Section("Informações") {
            TextField("Nome da receita", text: $name)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
                .focused($isNameFieldFocused)

            TextField("Descrição (opcional)", text: $descriptionText, axis: .vertical)
                .lineLimit(2...5)

            TextField("Link da receita", text: $externalURLString)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .autocorrectionDisabled()

            VStack(alignment: .leading, spacing: 8) {
                Text("Categorias")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(recipeCategories) { cat in
                        let isSelected = selectedCategories.contains(cat.name)
                        Button {
                            if isSelected {
                                selectedCategories.removeAll { $0 == cat.name }
                            } else {
                                selectedCategories.append(cat.name)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                IconImage(
                                    name: cat.name,
                                    iconFileName: cat.iconName,
                                    fallbackSymbol: "tag",
                                    size: 18,
                                    showBalloon: false
                                )
                                Text(cat.localizedDisplayName)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill), in: .capsule)
                            .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Picker("Dificuldade", selection: $difficulty) {
                ForEach(Difficulty.allCases) { d in
                    Text(d.displayName).tag(d)
                }
            }
        }
    }

    private var preparationMediaSection: some View {
        Section("Mídias da Receita") {
            Button {
                showPreparationMediaOptions = true
            } label: {
                Label("Adicionar Fotos ou Vídeos", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.plain)

            if !preparationMedia.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(preparationMedia) { media in
                            VStack(alignment: .leading, spacing: 8) {
                                preparationMediaPreview(for: media)
                                    .frame(width: 140, height: 110)
                                    .clipShape(.rect(cornerRadius: 14))

                                Text(media.type.label)
                                    .font(.caption.weight(.semibold))

                                Button("Remover", role: .destructive) {
                                    preparationMedia.removeAll { $0.id == media.id }
                                }
                                .font(.caption)
                            }
                            .frame(width: 140, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        Section("Detalhes") {
            Stepper("Preparo: \(prepTime) min", value: $prepTime, in: 0...600, step: 5)
            Stepper("Cozimento: \(cookTime) min", value: $cookTime, in: 0...600, step: 5)
            Stepper("Porções: \(servings)", value: $servings, in: 1...50)
            HStack {
                Text("Calorias")
                Spacer()
                TextField("kcal", text: $calories)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
        }
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        RecipeIngredientsSectionView(
            items: $ingredientItems,
            onIngredientIconTapped: { itemID in
                activeIngredientPicker = IngredientPickerTarget(id: itemID)
            }
        )
    }

    // MARK: - Steps

    private var stepsSection: some View {
        Section {
            ForEach($stepRows) { $row in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(row.order)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor, in: .circle)
                        .padding(.top, 4)

                    TextField("Descreva o passo...", text: $row.instruction, axis: .vertical)
                        .lineLimit(2...6)
                }
                .padding(.vertical, 4)
            }
            .onDelete { offsets in
                stepRows.remove(atOffsets: offsets)
                reorderSteps()
                if stepRows.isEmpty {
                    stepRows.append(StepRow(order: 1))
                }
            }

            Button("Adicionar Passo", systemImage: "plus.circle") {
                stepRows.append(StepRow(order: stepRows.count + 1))
            }
        } header: {
            Text("Modo de Preparo")
        }
    }

    // MARK: - Actions

    private func save() {
        let recipe = Recipe(
            name: name.trimmingCharacters(in: .whitespaces),
            descriptionText: descriptionText.trimmingCharacters(in: .whitespaces),
            imageData: imageData,
            externalURLString: externalURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            category: CategoryMutationService.normalizedRecipeCategoryString(
                from: selectedCategories.joined(separator: ", "),
                context: modelContext
            ),
            prepTime: prepTime,
            cookTime: cookTime,
            servings: servings,
            calories: Int(calories),
            difficulty: difficulty
        )
        modelContext.insert(recipe)

        recipe.requiredUtensils = utensilNames.map(\.name).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let commit = RecipeIngredientEditorPersistence.commit(items: ingredientItems)
        for section in commit.sections {
            section.recipe = recipe
            modelContext.insert(section)
        }
        for ingredient in commit.ingredients {
            ingredient.recipe = recipe
            modelContext.insert(ingredient)
        }

        for row in stepRows {
            let trimmedInstruction = row.instruction.trimmingCharacters(in: .whitespaces)
            guard !trimmedInstruction.isEmpty else { continue }
            let step = RecipeStep(order: row.order, instruction: trimmedInstruction)
            step.recipe = recipe
            modelContext.insert(step)
        }

        for (index, media) in preparationMedia.enumerated() {
            let attachment = RecipePreparationMedia(
                mediaType: media.type,
                data: media.data,
                fileExtension: media.fileExtension,
                sortOrder: index
            )
            attachment.recipe = recipe
            modelContext.insert(attachment)
        }

        dismiss()
    }

    private func normalizeSelectedCategoriesIfNeeded() {
        let resolved = selectedCategories.compactMap {
            CategoryMutationService.canonicalCategoryName(for: $0, type: .recipe, context: modelContext)
        }

        if resolved.isEmpty {
            selectedCategories = [CategoryMutationService.defaultRecipeCategoryName(context: modelContext)]
        } else if resolved != selectedCategories {
            selectedCategories = resolved
        }
    }

    private func loadPhoto() {
        Task {
            if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                await MainActor.run { imageData = data }
            }
        }
    }

    private func reorderSteps() {
        for i in stepRows.indices {
            stepRows[i].order = i + 1
        }
    }

    private func applyIngredientEntry(_ entry: ItemEntry, to rowID: UUID) {
        guard let index = ingredientItems.firstIndex(where: { $0.id == rowID }) else { return }
        ingredientItems[index].name = entry.preferredTitle(matching: ingredientItems[index].name)
        ingredientItems[index].iconName = entry.nomeDoArquivo
        ingredientItems[index].category = entry.categoria
    }

    private func applyIngredientIcon(_ entry: ItemEntry, to rowID: UUID) {
        guard let index = ingredientItems.firstIndex(where: { $0.id == rowID }) else { return }
        ingredientItems[index].iconName = entry.nomeDoArquivo
    }

    private func ingredientName(for rowID: UUID) -> String {
        ingredientItems.first(where: { $0.id == rowID })?.name ?? ""
    }

    private func ingredientIconName(for rowID: UUID) -> String? {
        ingredientItems.first(where: { $0.id == rowID })?.resolvedIconName
    }

    private func applyUtensilIcon(_ entry: ItemEntry, to utensilID: UUID) {
        guard let index = utensilNames.firstIndex(where: { $0.id == utensilID }) else { return }
        utensilNames[index].iconName = entry.nomeDoArquivo
    }

    private func utensilName(for utensilID: UUID) -> String {
        utensilNames.first(where: { $0.id == utensilID })?.name ?? ""
    }

    private func utensilIconName(for utensilID: UUID) -> String? {
        utensilNames.first(where: { $0.id == utensilID })?.iconName
    }

    private func loadPreparationMedia() {
        let items = selectedPreparationItems
        selectedPreparationItems = []

        Task {
            var loadedMedia = [DraftPreparationMedia]()
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let media = pickedRecipeMedia(from: data, contentType: item.supportedContentTypes.first)
                loadedMedia.append(DraftPreparationMedia(type: media.type, data: media.data, fileExtension: media.fileExtension))
            }
            await MainActor.run {
                preparationMedia.append(contentsOf: loadedMedia)
            }
        }
    }

    private func handleCoverFileImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        if let data = try? Data(contentsOf: url) {
            imageData = data
        }
    }

    private func handlePreparationFileImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else { return }
        let importedMedia = urls.compactMap { url -> DraftPreparationMedia? in
            guard url.startAccessingSecurityScopedResource() else { return nil }
            defer { url.stopAccessingSecurityScopedResource() }
            
            guard let data = try? Data(contentsOf: url) else { return nil }
            let media = pickedRecipeMedia(from: data, contentType: UTType(filenameExtension: url.pathExtension))
            return DraftPreparationMedia(type: media.type, data: media.data, fileExtension: media.fileExtension)
        }
        preparationMedia.append(contentsOf: importedMedia)
    }

    @ViewBuilder
    private func preparationMediaPreview(for media: DraftPreparationMedia) -> some View {
        switch media.type {
        case .photo:
            if let image = PlatformImage(data: media.data) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderMediaCard(icon: "photo", title: "Foto")
            }
        case .video:
            placeholderMediaCard(icon: "play.rectangle.fill", title: "Vídeo")
        }
    }

    private func placeholderMediaCard(icon: String, title: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemFill))
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DraftPreparationMedia: Identifiable {
    let id = UUID()
    let type: RecipePreparationMediaType
    let data: Data
    let fileExtension: String
}

// MARK: - Row Models

private struct StepRow: Identifiable {
    let id = UUID()
    var order: Int
    var instruction = ""
}

private struct IngredientPickerTarget: Identifiable {
    let id: UUID
}

private struct RecipeUtensilPickerTarget: Identifiable {
    let id: UUID
}
