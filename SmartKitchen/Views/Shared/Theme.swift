import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

// MARK: - Typography

extension Font {
    /// Playfair Display Bold — page titles (H1)
    static let pageTitle: Font = .custom("Playfair Display", size: 34, relativeTo: .largeTitle).weight(.bold)
    /// Playfair Display SemiBold — section titles (H2)
    static let sectionTitle: Font = .custom("Playfair Display", size: 24, relativeTo: .title).weight(.semibold)
    /// Playfair Display SemiBold — card & inline titles (H3)
    static let cardTitle: Font = .custom("Playfair Display", size: 18, relativeTo: .title3).weight(.semibold)
    /// Playfair Display Regular — decorative subtitle
    static let serifBody: Font = .custom("Playfair Display", size: 16, relativeTo: .body)
}

// MARK: - Glass / Material Helpers

extension View {
    /// Applies a glass-like material background with rounded corners.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
    }
}

struct CollapsibleSearchBar: View {
    @Binding var text: String
    @Binding var isPresented: Bool

    let placeholder: String

    @FocusState private var isFocused: Bool

    var body: some View {
        if isPresented {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($isFocused)
                    .submitLabel(.search)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        text = ""
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.tertiarySystemFill), in: .circle)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    }
            )
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
            .padding(.horizontal)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task {
                isFocused = true
            }
        }
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ScrollOffsetReader: View {
    let coordinateSpace: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named(coordinateSpace)).minY
                )
        }
        .frame(height: 0)
    }
}

extension View {
    func onScrollOffsetChange(perform action: @escaping (CGFloat) -> Void) -> some View {
        onPreferenceChange(ScrollOffsetPreferenceKey.self, perform: action)
    }
}

struct NeutralItemActionButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color(.tertiarySystemFill), in: .circle)
        }
        .buttonStyle(.plain)
    }
}

struct DragLiftPreviewCard: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: .rect(cornerRadius: 14)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 220, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
    }
}

struct DropTargetHighlight: View {
    var isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                isActive ? Color.accentColor.opacity(0.9) : .clear,
                style: StrokeStyle(lineWidth: 2, dash: [8, 6])
            )
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.08) : .clear)
            )
            .animation(.easeInOut(duration: 0.16), value: isActive)
    }
}

enum RecipeCameraPickerMode {
    case photoOnly
    case photoOrVideo
}

struct PickedRecipeMedia {
    let type: RecipePreparationMediaType
    let data: Data
    let fileExtension: String
}

func pickedRecipeMedia(from data: Data, contentType: UTType?) -> PickedRecipeMedia {
    let type: RecipePreparationMediaType = contentType?.conforms(to: .movie) == true ? .video : .photo
    let fileExtension = contentType?.preferredFilenameExtension ?? (type == .video ? "mov" : "jpg")
    return PickedRecipeMedia(type: type, data: data, fileExtension: fileExtension)
}

struct CameraMediaPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let mode: RecipeCameraPickerMode
    let onCapture: (PickedRecipeMedia) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.mediaTypes = mode == .photoOnly
            ? [UTType.image.identifier]
            : [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeMedium
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraMediaPicker

        init(_ parent: CameraMediaPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let mediaURL = info[.mediaURL] as? URL,
               let data = try? Data(contentsOf: mediaURL) {
                parent.onCapture(pickedRecipeMedia(from: data, contentType: .movie))
            } else if let image = info[.originalImage] as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.85) {
                parent.onCapture(pickedRecipeMedia(from: data, contentType: .image))
            }
            parent.dismiss()
        }
    }
}

struct CategoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query private var pantryItems: [PantryItem]
    @Query private var groceryItems: [GroceryItem]
    @Query private var recipes: [Recipe]

    let allowedTypes: [CategoryType]
    @State private var selectedType: CategoryType
    @State private var newCategoryName = ""

    init(initialType: CategoryType, allowedTypes: [CategoryType]? = nil) {
        let resolvedTypes = Array(Set((allowedTypes ?? [initialType]).map(\.canonicalType)))
            .sorted { lhs, rhs in
                let order: [CategoryType] = [.pantry, .recipe]
                return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
            }
        self.allowedTypes = resolvedTypes
        _selectedType = State(initialValue: initialType.canonicalType)
    }

    private var visibleCategories: [Category] {
        allCategories
            .filter { $0.type == selectedType.canonicalType }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            List {
                if allowedTypes.count > 1 {
                    Section("Grupo") {
                        Picker("Grupo", selection: $selectedType) {
                            ForEach(allowedTypes, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Categorias") {
                    ForEach(visibleCategories) { category in
                        TextField("Nome da categoria", text: Binding(
                            get: { category.name },
                            set: { category.name = $0 }
                        ))
                        .textInputAutocapitalization(.words)
                    }
                    .onMove(perform: moveCategories)
                    .onDelete(perform: deleteCategories)
                }

                Section("Nova categoria") {
                    HStack(spacing: 12) {
                        TextField("Adicionar categoria", text: $newCategoryName)
                            .textInputAutocapitalization(.words)

                        Button("Adicionar") {
                            addCategory()
                        }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Categorias")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !visibleCategories.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newCategoryName = ""
            return
        }

        let category = Category(
            name: trimmed,
            type: selectedType.canonicalType,
            sortOrder: visibleCategories.count
        )
        modelContext.insert(category)
        newCategoryName = ""
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var mutable = visibleCategories
        mutable.move(fromOffsets: source, toOffset: destination)
        for (index, category) in mutable.enumerated() {
            category.sortOrder = index
        }
    }

    private func deleteCategories(at offsets: IndexSet) {
        let categoriesToDelete = offsets.map { visibleCategories[$0] }
        let fallbackName = fallbackCategoryName(for: selectedType.canonicalType, excluding: categoriesToDelete)

        for category in categoriesToDelete {
            reassignEntities(from: category.name, to: fallbackName, type: category.type.canonicalType)
            modelContext.delete(category)
        }

        normalizeSortOrder(for: selectedType.canonicalType)
    }

    private func fallbackCategoryName(for type: CategoryType, excluding categories: [Category]) -> String {
        let excludedIds = Set(categories.map(\.id))
        let resolvedType = type.canonicalType

        if let existing = allCategories.first(where: {
            $0.type == resolvedType &&
            !excludedIds.contains($0.id) &&
            $0.name.localizedCaseInsensitiveCompare("Outros") == .orderedSame
        }) {
            return existing.name
        }

        let fallback = Category(name: "Outros", type: resolvedType, sortOrder: visibleCategories.count)
        modelContext.insert(fallback)
        return fallback.name
    }

    private func reassignEntities(from oldName: String, to newName: String, type: CategoryType) {
        switch type.canonicalType {
        case .pantry:
            for item in pantryItems where item.category == oldName {
                item.category = newName
            }
        case .grocery:
            for item in groceryItems where item.category == oldName {
                item.category = newName
            }
        case .recipe:
            for recipe in recipes where recipe.category == oldName {
                recipe.category = newName
            }
        }
    }

    private func normalizeSortOrder(for type: CategoryType) {
        let categories = allCategories
            .filter { $0.type == type.canonicalType }
            .sorted { $0.sortOrder < $1.sortOrder }

        for (index, category) in categories.enumerated() {
            category.sortOrder = index
        }
    }
}

// MARK: - Accent Color Options

enum AccentColorChoice: String, CaseIterable, Identifiable {
    case green
    case orange
    case blue

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .green:  Color("AccentGreen")
        case .orange: Color("AccentOrange")
        case .blue:   Color("AccentBlue")
        }
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .green:  "Verde"
        case .orange: "Laranja"
        case .blue:   "Azul"
        }
    }
}
