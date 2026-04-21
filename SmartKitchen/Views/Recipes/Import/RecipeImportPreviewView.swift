import SwiftUI
import SwiftData
import PhotosUI

/// Editable preview of an imported recipe draft.
/// Shows confidence badges on low-confidence fields and lets the user tweak
/// everything before saving. On save, converts to a SwiftData `Recipe`.
struct RecipeImportPreviewView: View {

    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    let initialDraft: RecipeDraft
    let onSave: (RecipeDraft) -> String?
    let onDiscard: () -> Void

    @State private var draft: RecipeDraft
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var saveErrorMessage: String?

    init(
        draft: RecipeDraft,
        onSave: @escaping (RecipeDraft) -> String?,
        onDiscard: @escaping () -> Void
    ) {
        self.initialDraft = draft
        self.onSave = onSave
        self.onDiscard = onDiscard
        self._draft = State(initialValue: draft)
    }

    private var recipeCategoryNames: [String] {
        allCategories.filter { $0.type == .recipe }.map(\.name)
    }

    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            if draft.overallConfidence != .high {
                confidenceBanner
            }

            Section("Capa") {
                coverSection
            }

            Section("Detalhes") {
                TextField("Nome da receita", text: $draft.name)
                    .font(.body.weight(.medium))
                confidenceHint(draft.nameConfidence, label: "Nome")

                TextField("Descrição", text: $draft.descriptionText, axis: .vertical)
                    .lineLimit(2...5)
                confidenceHint(draft.descriptionConfidence, label: "Descrição")

                if !draft.externalURLString.isEmpty {
                    HStack {
                        Image(systemName: "link")
                            .foregroundStyle(.tertiary)
                        Text(draft.externalURLString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if !draft.sourceLabel.isEmpty {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundStyle(.tertiary)
                        Text("Importado de \(draft.sourceLabel)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Categoria") {
                Picker("Categoria", selection: $draft.category) {
                    ForEach(allCategoryOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                confidenceHint(draft.categoryConfidence, label: "Categoria")
            }

            Section("Tempo e porções") {
                HStack {
                    Text("Preparo")
                    Spacer()
                    Stepper(
                        "\(draft.prepTime) min",
                        value: $draft.prepTime, in: 0...600, step: 5
                    )
                    .fixedSize()
                }
                HStack {
                    Text("Cozimento")
                    Spacer()
                    Stepper(
                        "\(draft.cookTime) min",
                        value: $draft.cookTime, in: 0...600, step: 5
                    )
                    .fixedSize()
                }
                HStack {
                    Text("Porções")
                    Spacer()
                    Stepper("\(draft.servings)", value: $draft.servings, in: 1...100)
                        .fixedSize()
                }
                Picker("Dificuldade", selection: $draft.difficulty) {
                    ForEach(Difficulty.allCases) { diff in
                        Label(diff.rawValue, systemImage: diff.icon).tag(diff)
                    }
                }
            }

            Section("Ingredientes (\(draft.ingredients.count))") {
                if draft.ingredients.isEmpty {
                    Text("Nenhum ingrediente reconhecido. Adicione manualmente.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach($draft.ingredients) { $ing in
                    ingredientRow($ing: $ing)
                }
                .onDelete { offsets in
                    draft.ingredients.remove(atOffsets: offsets)
                }
                Button {
                    draft.ingredients.append(IngredientDraft(confidence: .high))
                } label: {
                    Label("Adicionar ingrediente", systemImage: "plus.circle")
                }
            }

            Section("Modo de preparo (\(draft.steps.count))") {
                if draft.steps.isEmpty {
                    Text("Nenhum passo reconhecido.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach($draft.steps) { $step in
                    stepRow($step: $step)
                }
                .onDelete { offsets in
                    draft.steps.remove(atOffsets: offsets)
                    renumberSteps()
                }
                Button {
                    let nextOrder = (draft.steps.map(\.order).max() ?? 0) + 1
                    draft.steps.append(StepDraft(order: nextOrder, confidence: .high))
                } label: {
                    Label("Adicionar passo", systemImage: "plus.circle")
                }
            }

            if !draft.requiredUtensils.isEmpty {
                Section("Utensílios") {
                    ForEach(Array(draft.requiredUtensils.enumerated()), id: \.offset) { index, utensil in
                        TextField("Utensílio", text: Binding(
                            get: { draft.requiredUtensils[safe: index] ?? "" },
                            set: { draft.requiredUtensils[index] = $0 }
                        ))
                    }
                    .onDelete { offsets in
                        draft.requiredUtensils.remove(atOffsets: offsets)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Revisar receita")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Descartar", role: .destructive) {
                    onDiscard()
                }
                .tint(.red)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Salvar") {
                    save()
                }
                .font(.body.weight(.semibold))
                .disabled(!isValid)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) {
            loadNewPhoto()
        }
        .alert(
            "Não foi possível salvar",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        saveErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Tente novamente.")
        }
        .task {
            await fetchImageIfNeeded()
        }
    }

    // MARK: - Subviews

    private var confidenceBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Revise antes de salvar")
                    .font(.subheadline.weight(.semibold))
                Text("Alguns campos vieram com baixa confiança — eles estão marcados abaixo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.orange.opacity(0.08))
    }

    @ViewBuilder
    private var coverSection: some View {
        HStack {
            Group {
                if let data = draft.imageData, let uiImage = platformImage(from: data) {
                    #if os(iOS)
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    #else
                    Image(nsImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    #endif
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: 90, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                Button("Trocar imagem", systemImage: "photo.on.rectangle") {
                    showPhotoPicker = true
                }
                if draft.imageData != nil {
                    Button("Remover", systemImage: "trash", role: .destructive) {
                        draft.imageData = nil
                    }
                    .tint(.red)
                }
            }
            .font(.subheadline)

            Spacer()
        }
    }

    @ViewBuilder
    private func ingredientRow(@Binding ing: IngredientDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if ing.confidence == .low {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                TextField("Nome", text: $ing.name)
                    .font(.body.weight(.medium))
            }
            HStack(spacing: 8) {
                TextField(
                    "Qtd.",
                    value: $ing.quantity,
                    format: .number
                )
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .frame(maxWidth: 70)
                .textFieldStyle(.roundedBorder)

                Menu {
                    Button("—") { ing.unit = "" }
                    ForEach(RecipeOptionCatalog.unitOptions, id: \.fullName) { opt in
                        Button(opt.menuLabel) { ing.unit = opt.fullName }
                    }
                } label: {
                    Text(ing.unit.isEmpty ? "Unidade" : RecipeOptionCatalog.ingredientLabel(for: ing.unit, kind: .unit))
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground), in: .capsule)
                }

                Menu {
                    Button("—") { ing.preparationState = "" }
                    ForEach(RecipeOptionCatalog.stateOptions, id: \.fullName) { opt in
                        Button(opt.menuLabel) { ing.preparationState = opt.fullName }
                    }
                } label: {
                    Text(ing.preparationState.isEmpty ? "Estado" : ing.preparationState)
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground), in: .capsule)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func stepRow(@Binding step: StepDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("\(step.order)")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(PageTheme.recipes.accentColor, in: .circle)

                if step.confidence == .low {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                Spacer()
            }
            TextField("Descrição do passo", text: $step.instruction, axis: .vertical)
                .lineLimit(2...6)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func confidenceHint(_ confidence: FieldConfidence, label: String) -> some View {
        if confidence == .low {
            Label("\(label): baixa confiança, revise.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Actions

    private func renumberSteps() {
        for index in draft.steps.indices {
            draft.steps[index].order = index + 1
        }
    }

    private var allCategoryOptions: [String] {
        var options = Set(recipeCategoryNames)
        options.insert("Outros")
        if !draft.category.isEmpty { options.insert(draft.category) }
        return options.sorted()
    }

    private func save() {
        if let errorMessage = onSave(draft) {
            saveErrorMessage = errorMessage
        }
    }

    private func loadNewPhoto() {
        guard let item = selectedPhoto else { return }
        Task { @MainActor in
            if let data = try? await item.loadTransferable(type: Data.self) {
                draft.imageData = data
            }
        }
    }

    /// Fetches the remote cover image if we have URL but not data yet.
    private func fetchImageIfNeeded() async {
        guard draft.imageData == nil, let url = draft.imageURL else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await MainActor.run { draft.imageData = data }
        } catch {
            // non-fatal
        }
    }

    private func platformImage(from data: Data) -> PlatformImage? {
        #if os(iOS)
        return UIImage(data: data)
        #else
        return NSImage(data: data)
        #endif
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
