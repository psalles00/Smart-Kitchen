import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct EditRecipeView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

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

    private var recipeCategories: [Category] {
        allCategories.filter { $0.type == .recipe }
    }

    var body: some View {
        rootContent
    }

    private var rootContent: some View {
        Form {
            imageSection
            basicInfoSection
            detailsSection
            preparationMediaSection
            ingredientsSection
            stepsSection
        }
        .navigationTitle("Editar Receita")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { save() }
                    .fontWeight(.semibold)
            }
            ToolbarItem(placement: .topBarTrailing) {
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
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCameraPicker = true
                } else {
                    showCameraUnavailableAlert = true
                }
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
            CameraMediaPicker(mode: .photoOnly) { media in
                recipe.imageData = media.data
            }
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagementView(initialType: .recipe)
        }
        .sheet(isPresented: $showPreparationCameraPicker) {
            CameraMediaPicker(mode: .photoOrVideo) { media in
                preparationMediaRows.append(
                    EditPreparationMediaRow(
                        type: media.type,
                        data: media.data,
                        fileExtension: media.fileExtension
                    )
                )
            }
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
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showPreparationCameraPicker = true
                } else {
                    showCameraUnavailableAlert = true
                }
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
                    if let data = recipe.imageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
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
                .textInputAutocapitalization(.words)

            TextField("Descrição (opcional)", text: $recipe.descriptionText, axis: .vertical)
                .lineLimit(2...5)

            TextField("Link externo (URL)", text: $recipe.externalURLString)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
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
                VStack(spacing: 8) {
                    TextField("Ingrediente", text: $row.name)
                        .textInputAutocapitalization(.words)
                    HStack {
                        TextField("Qtd", text: $row.quantity)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                        TextField("Unidade", text: $row.unit)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

        ingredientRows = recipe.ingredients
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ing in
                EditIngredientRow(
                    existingId: ing.id,
                    name: ing.name,
                    quantity: ing.quantity.map {
                        $0.truncatingRemainder(dividingBy: 1) == 0
                            ? String(format: "%.0f", $0) : String(format: "%.1f", $0)
                    } ?? "",
                    unit: ing.unit
                )
            }

        stepRows = recipe.steps
            .sorted { $0.order < $1.order }
            .map { step in
                EditStepRow(existingId: step.id, order: step.order, instruction: step.instruction)
            }

        preparationMediaRows = recipe.preparationMedia
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { media in
                EditPreparationMediaRow(
                    existingId: media.id,
                    type: media.mediaType,
                    data: media.data,
                    fileExtension: media.fileExtension
                )
            }
    }

    private func save() {
        recipe.updatedAt = .now

        // Update ingredients — remove old, insert new
        for ing in recipe.ingredients {
            modelContext.delete(ing)
        }
        for (index, row) in ingredientRows.enumerated() {
            let trimmed = row.name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let ingredient = RecipeIngredient(
                name: trimmed,
                quantity: Double(row.quantity),
                unit: row.unit.trimmingCharacters(in: .whitespaces),
                sortOrder: index
            )
            ingredient.recipe = recipe
            modelContext.insert(ingredient)
        }

        // Update steps
        for step in recipe.steps {
            modelContext.delete(step)
        }
        for row in stepRows {
            let trimmed = row.instruction.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let step = RecipeStep(order: row.order, instruction: trimmed)
            step.recipe = recipe
            modelContext.insert(step)
        }

        for media in recipe.preparationMedia {
            modelContext.delete(media)
        }
        for (index, media) in preparationMediaRows.enumerated() {
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
        guard case let .success(url) = result,
              let data = try? Data(contentsOf: url) else { return }
        recipe.imageData = data
    }

    private func handlePreparationFileImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else { return }
        let importedMedia = urls.compactMap { url -> EditPreparationMediaRow? in
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
            if let image = UIImage(data: media.data) {
                Image(uiImage: image)
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
