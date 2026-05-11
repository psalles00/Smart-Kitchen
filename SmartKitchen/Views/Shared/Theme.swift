import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Superfície neutra adaptativa usada por cards, chips, barras de filtro,
/// botões da Home, etc.
/// - Light: `#F8F8FA`
/// - Dark:  `#2C2C2E`
let neutralSurfaceColor: Color = {
    #if canImport(UIKit)
    return Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x2C / 255.0, green: 0x2C / 255.0, blue: 0x2E / 255.0, alpha: 1)
            : UIColor(red: 248 / 255.0, green: 248 / 255.0, blue: 250 / 255.0, alpha: 1)
    })
    #elseif canImport(AppKit)
    return Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0x2C / 255.0, green: 0x2C / 255.0, blue: 0x2E / 255.0, alpha: 1)
            : NSColor(srgbRed: 248 / 255.0, green: 248 / 255.0, blue: 250 / 255.0, alpha: 1)
    } ?? NSColor(srgbRed: 248 / 255.0, green: 248 / 255.0, blue: 250 / 255.0, alpha: 1))
    #else
    return Color(red: 248 / 255, green: 248 / 255, blue: 250 / 255)
    #endif
}()

/// Fundo principal das telas (área onde antes era branco).
/// - Light: `#FFFFFF`
/// - Dark:  `#19191A`
let appPrimaryBackground: Color = {
    #if canImport(UIKit)
    return Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x19 / 255.0, green: 0x19 / 255.0, blue: 0x1A / 255.0, alpha: 1)
            : UIColor.white
    })
    #elseif canImport(AppKit)
    return Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0x19 / 255.0, green: 0x19 / 255.0, blue: 0x1A / 255.0, alpha: 1)
            : NSColor.white
    } ?? NSColor.windowBackgroundColor)
    #else
    return Color.white
    #endif
}()

/// Cor da divisória de itens em listas no modo escuro (`#545458`). No modo
/// claro mantemos a estética dashed atual via `Color.primary`/`Color.white`.
let listItemDividerDarkColor = Color(red: 0x54 / 255.0, green: 0x54 / 255.0, blue: 0x58 / 255.0)

// MARK: - Typography

extension Font {
    /// Bricolage Grotesque — page titles (H1)
    static let pageTitle: Font = .custom("Bricolage Grotesque", size: 34, relativeTo: .largeTitle).bold()
    /// Bricolage Grotesque — sheet and modal navigation titles
    static let modalTitle: Font = .custom("Bricolage Grotesque", size: 18, relativeTo: .headline)
    /// Bricolage Grotesque — section titles (H2)
    static let sectionTitle: Font = .custom("Bricolage Grotesque", size: 24, relativeTo: .title).bold()
    /// Bricolage Grotesque — card & inline titles (H3)
    static let cardTitle: Font = .custom("Bricolage Grotesque", size: 18, relativeTo: .title3).bold()
    /// Bricolage Grotesque — decorative subtitle
    static let serifBody: Font = .custom("Bricolage Grotesque", size: 16, relativeTo: .body)
}

// MARK: - Glass Header Button Group

/// Groups multiple header buttons into a single pill
struct GlassButtonGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .foregroundStyle(.white)
    }
}

/// An inner button for GlassButtonGroup
struct GlassGroupButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// An inner menu for GlassButtonGroup
struct GlassGroupMenu<Content: View>: View {
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 36)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
    }
}

/// A visual separator for styling within GlassButtonGroup
struct GlassGroupDivider: View {
    var body: some View {
        EmptyView()
    }
}

struct ItemListDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                colorScheme == .dark
                    ? listItemDividerDarkColor.opacity(0.95)
                    : Color.white.opacity(0.34),
                style: StrokeStyle(lineWidth: 0.9, lineCap: .round, dash: [1.0, 3.6])
            )
            .background(
                Capsule(style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? listItemDividerDarkColor
                            : Color.primary.opacity(0.1),
                        style: StrokeStyle(lineWidth: 0.9, lineCap: .round, dash: [1.0, 3.6], dashPhase: 1.8)
                    )
            )
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Glass / Material Helpers

extension View {
    /// Applies a glass-like material background with rounded corners.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
    }

    /// Applies the shared branded title style used in modal navigation bars.
    func modalNavigationTitle(_ title: String) -> some View {
        modifier(ModalNavigationTitleModifier(title: title))
    }

    /// Settings screens are pushed inside the macOS settings navigation stack,
    /// not shown as standalone modals. Avoid forcing a separate color-scheme
    /// preference there during the push transition.
    func settingsNavigationTitle(_ title: String) -> some View {
#if os(iOS)
        modalNavigationTitle(title)
#else
        self
#endif
    }
}

private struct ModalNavigationTitleModifier: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.modalTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
#endif
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

// MARK: - Animated Item Action Button (LifeOS-style)

@MainActor
private final class CheckboxActionDelayCoordinator {
    static let shared = CheckboxActionDelayCoordinator()

    private struct PendingAction {
        let key: String
        let action: () -> Void
        let onExecuted: (() -> Void)?
    }

    private var pendingActions: [PendingAction] = []
    private var revision: Int = 0
    private var worker: Task<Void, Never>?

    func enqueueOrCancel(
        key: String,
        action: @escaping () -> Void,
        onExecuted: (() -> Void)? = nil
    ) -> Bool {
        if let index = pendingActions.firstIndex(where: { $0.key == key }) {
            pendingActions.remove(at: index)
            revision += 1
            return false
        }

        pendingActions.append(
            PendingAction(
                key: key,
                action: action,
                onExecuted: onExecuted
            )
        )
        revision += 1

        if worker == nil {
            worker = Task { @MainActor in
                await self.drainWhenStable()
            }
        }

        return true
    }

    private func drainWhenStable() async {
        while true {
            let snapshot = revision
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }

            // A newer tap arrived; restart the 2-second window.
            if snapshot != revision {
                continue
            }

            let actions = pendingActions
            pendingActions.removeAll()
            actions.forEach {
                $0.action()
                $0.onExecuted?()
            }

            worker = nil
            return
        }
    }
}

/// An animated circular button that fills with color and reveals an icon when tapped.
struct AnimatedItemActionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let actionID: String
    let systemImage: String
    let initialSystemImage: String
    let color: Color
    let action: () -> Void

    private let size: CGFloat = 32
    private let lineWidth: CGFloat = 4.5

    @State private var strokeProgress: CGFloat = 0
    @State private var fillOpacity: CGFloat = 0
    @State private var showIcon: Bool = false
    @State private var iconScale: CGFloat = 0
    @State private var isPending: Bool = false

    init(
        actionID: String,
        systemImage: String,
        initialSystemImage: String? = nil,
        color: Color,
        action: @escaping () -> Void
    ) {
        self.actionID = actionID
        self.systemImage = systemImage
        self.initialSystemImage = initialSystemImage ?? systemImage
        self.color = color
        self.action = action
    }

    var body: some View {
        Button {
            HapticManager.impact(style: .medium)
            let wasEnqueued = CheckboxActionDelayCoordinator.shared.enqueueOrCancel(
                key: actionID,
                action: action
            ) {
                Task { @MainActor in
                    await finishAnimationAfterAction()
                }
            }

            if wasEnqueued {
                animateAndPerform()
            } else {
                cancelPendingAnimation()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(lineWidth: lineWidth)
                    .foregroundColor(uncheckedColor)
                    .frame(width: size, height: size)

                Circle()
                    .trim(from: 0, to: strokeProgress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color, color.opacity(0.7), color]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .opacity(fillOpacity)

                Image(systemName: initialSystemImage)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundColor(uncheckedIconColor)
                    .opacity(showIcon ? 0 : 1)

                Image(systemName: systemImage)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(showIcon ? 1 : 0)
                    .scaleEffect(iconScale)
            }
        }
        .buttonStyle(.plain)
    }

    private var uncheckedColor: Color {
        colorScheme == .dark
            ? Color(red: 0x54 / 255.0, green: 0x54 / 255.0, blue: 0x58 / 255.0)
            : Color(red: 243/255, green: 243/255, blue: 244/255)
    }

    private var uncheckedIconColor: Color {
        uncheckedColor
    }

    private func animateAndPerform() {
        isPending = true
        strokeProgress = 0
        fillOpacity = 0
        showIcon = false
        iconScale = 0

        withAnimation(.easeInOut(duration: 0.25)) {
            strokeProgress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.easeIn(duration: 0.1)) {
                fillOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(50))
            showIcon = true
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0)) {
                iconScale = 1
            }
            HapticManager.impact(style: .light)
        }
    }

    private func cancelPendingAnimation() {
        guard isPending else { return }

        withAnimation(.easeOut(duration: 0.18)) {
            iconScale = 0
            fillOpacity = 0
            strokeProgress = 0
        }

        withAnimation(.easeOut(duration: 0.12).delay(0.05)) {
            showIcon = false
        }

        isPending = false
    }

    @MainActor
    private func finishAnimationAfterAction() async {
        // Keep the marked state visible until the action has actually run.
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.easeOut(duration: 0.2)) {
            iconScale = 0
            fillOpacity = 0
        }
        try? await Task.sleep(for: .milliseconds(150))
        showIcon = false
        withAnimation(.easeOut(duration: 0.2)) {
            strokeProgress = 0
        }
        try? await Task.sleep(for: .milliseconds(250))
        isPending = false
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

struct PhotoPreviewSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let image: PlatformImage

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ZoomablePhotoView(image: image)
            }
            .toolbar {
                ToolbarItem(placement: .adaptiveLeading) {
                    Button("Fechar") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            #if os(iOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
        }
    }
}

struct ZoomablePhotoView: View {
    let image: PlatformImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(lastScale * value, 1), 4)
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                            if scale > 1 {
                                scale = 1
                                lastScale = 1
                            } else {
                                scale = 2
                                lastScale = 2
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#if os(iOS)
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
#endif

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
