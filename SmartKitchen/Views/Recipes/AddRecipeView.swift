import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct AddRecipeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    // Basic info
    @State private var name = ""
    @State private var descriptionText = ""
    @State private var selectedCategory = "Outros"
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
    @State private var ingredientRows: [IngredientRow] = [IngredientRow()]

    // Dynamic steps
    @State private var stepRows: [StepRow] = [StepRow(order: 1)]

    private var recipeCategories: [Category] {
        allCategories.filter { $0.type == .recipe }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
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
        .navigationTitle("Nova Receita")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { save() }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCategoryManager = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .onChange(of: selectedPhoto) {
            loadPhoto()
        }
        .onChange(of: selectedPreparationItems) {
            loadPreparationMedia()
        }
        .confirmationDialog("Adicionar Foto", isPresented: $showPhotoOptions, titleVisibility: .visible) {
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

            if imageData != nil {
                Button("Remover Foto", role: .destructive) {
                    imageData = nil
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
                imageData = media.data
            }
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagementView(initialType: .recipe)
        }
        .sheet(isPresented: $showPreparationCameraPicker) {
            CameraMediaPicker(mode: .photoOrVideo) { media in
                preparationMedia.append(
                    DraftPreparationMedia(
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
                    if let imageData, let uiImage = UIImage(data: imageData) {
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
                .textInputAutocapitalization(.words)

            TextField("Descrição (opcional)", text: $descriptionText, axis: .vertical)
                .lineLimit(2...5)

            TextField("Link externo (URL)", text: $externalURLString)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()

            Picker("Categoria", selection: $selectedCategory) {
                ForEach(recipeCategories) { cat in
                    Text(cat.name).tag(cat.name)
                }
            }

            Picker("Dificuldade", selection: $difficulty) {
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
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
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
                        TextField("Unidade (g, ml, xícara...)", text: $row.unit)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .onDelete { offsets in
                ingredientRows.remove(atOffsets: offsets)
                if ingredientRows.isEmpty {
                    ingredientRows.append(IngredientRow())
                }
            }

            Button("Adicionar Ingrediente", systemImage: "plus.circle") {
                ingredientRows.append(IngredientRow())
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
            category: selectedCategory,
            prepTime: prepTime,
            cookTime: cookTime,
            servings: servings,
            calories: Int(calories),
            difficulty: difficulty
        )
        modelContext.insert(recipe)

        for (index, row) in ingredientRows.enumerated() {
            let trimmedName = row.name.trimmingCharacters(in: .whitespaces)
            guard !trimmedName.isEmpty else { continue }
            let ingredient = RecipeIngredient(
                name: trimmedName,
                quantity: Double(row.quantity),
                unit: row.unit.trimmingCharacters(in: .whitespaces),
                sortOrder: index
            )
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
        guard case let .success(url) = result,
              let data = try? Data(contentsOf: url) else { return }
        imageData = data
    }

    private func handlePreparationFileImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else { return }
        let importedMedia = urls.compactMap { url -> DraftPreparationMedia? in
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

private struct DraftPreparationMedia: Identifiable {
    let id = UUID()
    let type: RecipePreparationMediaType
    let data: Data
    let fileExtension: String
}

// MARK: - Row Models

private struct IngredientRow: Identifiable {
    let id = UUID()
    var name = ""
    var quantity = ""
    var unit = ""
}

private struct StepRow: Identifiable {
    let id = UUID()
    var order: Int
    var instruction = ""
}
