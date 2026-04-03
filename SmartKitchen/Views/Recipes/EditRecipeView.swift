import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct EditRecipeView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query private var settingsArray: [AppSettings]

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var ingredientRows: [EditIngredientRow] = []
    @State private var stepRows: [EditStepRow] = []
    @State private var initialized = false
    @State private var showPhotoOptions = false
    @State private var showPhotoLibrary = false
    @State private var showCameraPicker = false
    @State private var showPhotoFileImporter = false
    @State private var showCameraUnavailableAlert = false
    @State private var showCategoryManager = false
    @State private var selectedPreparationItems: [PhotosPickerItem] = []
    @State private var preparationMediaRows: [EditPreparationMediaRow] = []
    @State private var showPreparationMediaOptions = false
    @State private var showPreparationPhotoLibrary = false
    @State private var showPreparationCameraPicker = false
    @State private var showPreparationFileImporter = false
    @State private var utensilNames: [IdentifiedUtensil] = []
    @State private var activeIngredientPicker: EditIngredientPickerTarget?
    @State private var activeUtensilPicker: EditUtensilPickerTarget?

    private var settings: AppSettings? { settingsArray.first }

    private var recipeCategories: [Category] {
        allCategories.filter { $0.type == .recipe }
    }

    var body: some View {
        rootContent
            .formStyle(.grouped)
            #if os(macOS)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .frame(minWidth: 700, minHeight: 800)
            #endif
    }

    private var rootContent: some View {
        Form {
            imageSection
            basicInfoSection
            detailsSection
            preparationMediaSection
            ingredientsSection
            if settings?.showUtensils == true {
                RecipeUtensilsEditor(
                    utensilNames: $utensilNames,
                    onIconTapped: { activeUtensilPicker = EditUtensilPickerTarget(id: $0) }
                )
            }
            stepsSection
        }
        .navigationTitle("Editar Receita")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .tint(PageTheme.recipes.accentColor)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { save() }
                    .fontWeight(.semibold)
            }
            ToolbarItem(placement: .adaptiveTrailing) {
                Button {
                    showCategoryManager = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .onAppear { loadData() }
        .onChange(of: selectedPhoto) { loadPhoto() }
        .onChange(of: selectedPreparationItems) { loadPreparationMedia() }
        .confirmationDialog("Foto da Receita", isPresented: $showPhotoOptions, titleVisibility: .visible) {
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
                showPhotoFileImporter = true
            }

            if recipe.imageData != nil {
                Button("Remover Foto", role: .destructive) {
                    recipe.imageData = nil
                    selectedPhoto = nil
                }
            }
        }
        .photosPicker(isPresented: $showPhotoLibrary, selection: $selectedPhoto, matching: .images)
        .fileImporter(
            isPresented: $showPhotoFileImporter,
            allowedContentTypes: [.image]
        ) { result in
            handleCoverFileImport(result)
        }
        .sheet(isPresented: $showCameraPicker) {
            #if os(iOS)
            CameraMediaPicker(mode: .photoOnly) { media in
                recipe.imageData = media.data
            }
            #else
            MacCameraMediaPicker(mode: .photoOnly) { media in
                recipe.imageData = media.data
            }
            .frame(minWidth: 640, minHeight: 520)
            #endif
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagementView(initialType: .recipe)
        }
        .sheet(item: $activeIngredientPicker) { target in
            ItemIconPickerView(
                initialQuery: ingredientName(for: target.id),
                currentIconFileName: ingredientIconName(for: target.id),
                fallbackSymbol: "leaf"
            ) { entry in
                applyIngredientIcon(entry, to: target.id)
            }
        }
        .sheet(item: $activeUtensilPicker) { target in
            ItemIconPickerView(
                initialQuery: utensilName(for: target.id),
                currentIconFileName: utensilIconName(for: target.id),
                fallbackSymbol: "fork.knife"
            ) { entry in
                applyUtensilIcon(entry, to: target.id)
            }
        }
        .sheet(isPresented: $showPreparationCameraPicker) {
            #if os(iOS)
            CameraMediaPicker(mode: .photoOrVideo) { media in
                preparationMediaRows.append(
                    EditPreparationMediaRow(
                        type: media.type,
                        data: media.data,
                        fileExtension: media.fileExtension
                    )
                )
            }
            #else
            MacCameraMediaPicker(mode: .photoOnly) { media in
                preparationMediaRows.append(
                    EditPreparationMediaRow(
                        type: media.type,
                        data: media.data,
                        fileExtension: media.fileExtension
                    )
                )
            }
            .frame(minWidth: 640, minHeight: 520)
            #endif
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
                showPreparationFileImporter = true
            }
        }
    }

    // MARK: - Image

    private var imageSection: some View {
        Section {
            Button {
                showPhotoOptions = true
            } label: {
                ZStack(alignment: .bottomLeading) {
                    if let data = recipe.imageData, let image = PlatformImage(data: data) {
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

                    if recipe.imageData != nil {
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
            TextField("Nome da receita", text: $recipe.name)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif

            TextField("Descrição (opcional)", text: $recipe.descriptionText, axis: .vertical)
                .lineLimit(2...5)

            TextField("Link externo (URL)", text: $recipe.externalURLString)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .autocorrectionDisabled()

            Picker("Categoria", selection: $recipe.category) {
                ForEach(recipeCategories) { cat in
                    Text(cat.name).tag(cat.name)
                }
            }

            Picker("Dificuldade", selection: $recipe.difficulty) {
                ForEach(Difficulty.allCases) { d in
                    Text(d.rawValue).tag(d)
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

            if !preparationMediaRows.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(preparationMediaRows) { media in
                            VStack(alignment: .leading, spacing: 8) {
                                preparationMediaPreview(for: media)
                                    .frame(width: 140, height: 110)
                                    .clipShape(.rect(cornerRadius: 14))

                                Text(media.type.label)
                                    .font(.caption.weight(.semibold))

                                Button("Remover", role: .destructive) {
                                    preparationMediaRows.removeAll { $0.id == media.id }
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
            Stepper("Preparo: \(recipe.prepTime) min", value: $recipe.prepTime, in: 0...600, step: 5)
            Stepper("Cozimento: \(recipe.cookTime) min", value: $recipe.cookTime, in: 0...600, step: 5)
            Stepper("Porções: \(recipe.servings)", value: $recipe.servings, in: 1...50)
        }
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        Section {
            ForEach($ingredientRows) { $row in
                VStack(alignment: .leading, spacing: 8) {
                    ItemSearchField(
                        text: $row.name,
                        placeholder: "Ingrediente",
                        iconFileName: row.iconName,
                        fallbackSymbol: "leaf",
                        showsLeadingIcon: true,
                        onIconTapped: { activeIngredientPicker = EditIngredientPickerTarget(id: row.id) }
                    ) { entry in
                        row.name = entry.preferredTitle(matching: row.name)
                        row.iconName = entry.nomeDoArquivo
                        row.category = entry.categoria
                    }

                    ingredientMetadataRow(for: $row)
                }
                .padding(.vertical, 4)
            }
            .onDelete { offsets in
                ingredientRows.remove(atOffsets: offsets)
            }

            Button("Adicionar Ingrediente", systemImage: "plus.circle") {
                ingredientRows.append(EditIngredientRow())
            }
        } header: {
            Text("Ingredientes")
        }
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
            }

            Button("Adicionar Passo", systemImage: "plus.circle") {
                stepRows.append(EditStepRow(order: stepRows.count + 1))
            }
        } header: {
            Text("Modo de Preparo")
        }
    }

    // MARK: - Actions

    private func loadData() {
        guard !initialized else { return }
        initialized = true

        ingredientRows = (recipe.ingredients ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ing in
                EditIngredientRow(
                    existingId: ing.id,
                    name: ing.name,
                    quantity: ing.quantity.map {
                        $0.truncatingRemainder(dividingBy: 1) == 0
                            ? String(format: "%.0f", $0) : String(format: "%.1f", $0)
                    } ?? "",
                    unit: ing.unit,
                    preparationState: ing.preparationState,
                    category: ItemDatabase.shared.entry(forFilename: ing.iconName ?? "")?.categoria ?? ItemDatabase.shared.exactMatch(for: ing.name)?.categoria,
                    iconName: ing.iconName
                )
            }

        stepRows = (recipe.steps ?? [])
            .sorted { $0.order < $1.order }
            .map { step in
                EditStepRow(existingId: step.id, order: step.order, instruction: step.instruction)
            }

        preparationMediaRows = (recipe.preparationMedia ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { media in
                EditPreparationMediaRow(
                    existingId: media.id,
                    type: media.mediaType,
                    data: media.data,
                    fileExtension: media.fileExtension
                )
            }

        utensilNames = (recipe.requiredUtensils ?? []).map { name in
            let match = ItemDatabase.shared.exactMatch(for: name)
            return IdentifiedUtensil(
                name: name,
                category: match?.categoria,
                iconName: match?.nomeDoArquivo
            )
        }
    }

    private func save() {
        recipe.updatedAt = .now
        recipe.requiredUtensils = utensilNames.map { $0.name }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Update ingredients — remove old, insert new
        for ing in (recipe.ingredients ?? []) {
            modelContext.delete(ing)
        }
        var newIngredients: [RecipeIngredient] = []
        for (index, row) in ingredientRows.enumerated() {
            let trimmed = row.name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let ingredient = RecipeIngredient(
                name: trimmed,
                quantity: Double(row.quantity),
                unit: row.unit.trimmingCharacters(in: .whitespaces),
                preparationState: row.preparationState.trimmingCharacters(in: .whitespacesAndNewlines),
                iconName: row.iconName ?? ItemDatabase.shared.exactMatch(for: trimmed)?.nomeDoArquivo,
                sortOrder: index
            )
            ingredient.recipe = recipe
            modelContext.insert(ingredient)
            newIngredients.append(ingredient)
        }
        recipe.ingredients = newIngredients

        // Update steps
        for step in (recipe.steps ?? []) {
            modelContext.delete(step)
        }
        var newSteps: [RecipeStep] = []
        for row in stepRows {
            let trimmed = row.instruction.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let step = RecipeStep(order: row.order, instruction: trimmed)
            step.recipe = recipe
            modelContext.insert(step)
            newSteps.append(step)
        }
        recipe.steps = newSteps

        for media in (recipe.preparationMedia ?? []) {
            modelContext.delete(media)
        }
        var newMedia: [RecipePreparationMedia] = []
        for (index, media) in preparationMediaRows.enumerated() {
            let attachment = RecipePreparationMedia(
                mediaType: media.type,
                data: media.data,
                fileExtension: media.fileExtension,
                sortOrder: index
            )
            attachment.recipe = recipe
            modelContext.insert(attachment)
            newMedia.append(attachment)
        }
        recipe.preparationMedia = newMedia

        dismiss()
    }

    private func loadPhoto() {
        Task {
            if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                await MainActor.run { recipe.imageData = data }
            }
        }
    }

    private func reorderSteps() {
        for i in stepRows.indices {
            stepRows[i].order = i + 1
        }
    }

    private func applyIngredientEntry(_ entry: ItemEntry, to rowID: UUID) {
        guard let index = ingredientRows.firstIndex(where: { $0.id == rowID }) else { return }
        ingredientRows[index].name = entry.preferredTitle(matching: ingredientRows[index].name)
        ingredientRows[index].iconName = entry.nomeDoArquivo
        ingredientRows[index].category = entry.categoria
    }

    private func applyIngredientIcon(_ entry: ItemEntry, to rowID: UUID) {
        guard let index = ingredientRows.firstIndex(where: { $0.id == rowID }) else { return }
        ingredientRows[index].iconName = entry.nomeDoArquivo
    }

    @ViewBuilder
    private func ingredientMetadataRow(for row: Binding<EditIngredientRow>) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("Qtd", text: row.quantity)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .frame(width: 44)

                RecipeOptionMenuField(kind: .unit, selection: row.unit)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 34)

            RecipeOptionMenuField(kind: .state, selection: row.preparationState)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func ingredientName(for rowID: UUID) -> String {
        ingredientRows.first(where: { $0.id == rowID })?.name ?? ""
    }

    private func ingredientIconName(for rowID: UUID) -> String? {
        ingredientRows.first(where: { $0.id == rowID })?.iconName
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
            var loadedMedia = [EditPreparationMediaRow]()
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let media = pickedRecipeMedia(from: data, contentType: item.supportedContentTypes.first)
                loadedMedia.append(EditPreparationMediaRow(type: media.type, data: media.data, fileExtension: media.fileExtension))
            }
            await MainActor.run {
                preparationMediaRows.append(contentsOf: loadedMedia)
            }
        }
    }

    private func handleCoverFileImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        if let data = try? Data(contentsOf: url) {
            recipe.imageData = data
        }
    }

    private func handlePreparationFileImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else { return }
        let importedMedia = urls.compactMap { url -> EditPreparationMediaRow? in
            guard url.startAccessingSecurityScopedResource() else { return nil }
            defer { url.stopAccessingSecurityScopedResource() }
            
            guard let data = try? Data(contentsOf: url) else { return nil }
            let media = pickedRecipeMedia(from: data, contentType: UTType(filenameExtension: url.pathExtension))
            return EditPreparationMediaRow(type: media.type, data: media.data, fileExtension: media.fileExtension)
        }
        preparationMediaRows.append(contentsOf: importedMedia)
    }

    @ViewBuilder
    private func preparationMediaPreview(for media: EditPreparationMediaRow) -> some View {
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

// MARK: - Row Models

private struct EditIngredientRow: Identifiable {
    let id = UUID()
    var existingId: UUID?
    var name = ""
    var quantity = ""
    var unit = ""
    var preparationState = ""
    var category: String?
    var iconName: String?
}

private struct EditStepRow: Identifiable {
    let id = UUID()
    var existingId: UUID?
    var order: Int = 1
    var instruction = ""
}

private struct EditPreparationMediaRow: Identifiable {
    let id: UUID
    let existingId: UUID?
    var type: RecipePreparationMediaType
    var data: Data
    var fileExtension: String

    init(
        existingId: UUID? = nil,
        type: RecipePreparationMediaType,
        data: Data,
        fileExtension: String
    ) {
        self.id = existingId ?? UUID()
        self.existingId = existingId
        self.type = type
        self.data = data
        self.fileExtension = fileExtension
    }
}

private struct EditIngredientPickerTarget: Identifiable {
    let id: UUID
}

private struct EditUtensilPickerTarget: Identifiable {
    let id: UUID
}
