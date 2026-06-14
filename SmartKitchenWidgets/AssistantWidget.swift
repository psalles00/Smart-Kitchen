import WidgetKit
import SwiftUI

// MARK: - Deep link

/// The app handles this URL in `SmartKitchenApp.onOpenURL`: it reveals the
/// fullscreen assistant in idle (search) mode — NOT AI chat.
private let assistantDeepLink = URL(string: "smartkitchen://assistant")!

// MARK: - Timeline

struct AssistantEntry: TimelineEntry {
    let date: Date
}

struct AssistantProvider: TimelineProvider {
    func placeholder(in context: Context) -> AssistantEntry {
        AssistantEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (AssistantEntry) -> Void) {
        completion(AssistantEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AssistantEntry>) -> Void) {
        // The widget is static. Refresh once a day just so WidgetKit keeps
        // the timeline warm; the visual state doesn't actually change.
        let now = Date()
        let next = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [AssistantEntry(date: now)], policy: .after(next)))
    }
}

// MARK: - Widget

struct AssistantWidget: Widget {
    let kind: String = "AssistantWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AssistantProvider()) { entry in
            AssistantWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(assistantDeepLink)
        }
        .configurationDisplayName("Assistente")
        .description("Abre o Savoria direto na conversa com o assistente, com o teclado pronto.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .systemSmall,
        ])
    }
}

// MARK: - Root view (dispatches on family)

struct AssistantWidgetView: View {
    let entry: AssistantEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            AssistantCircularView()
        case .accessoryRectangular:
            AssistantRectangularView()
        case .accessoryInline:
            AssistantInlineView()
        case .systemSmall:
            AssistantSmallView()
        default:
            AssistantCircularView()
        }
    }
}

// MARK: - Lock Screen: Circular

private struct AssistantCircularView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
        }
        .widgetAccentable()
    }
}

// MARK: - Lock Screen: Rectangular

private struct AssistantRectangularView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text("Assistente")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .widgetAccentable()
                Text("Pergunte qualquer coisa")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Lock Screen: Inline

private struct AssistantInlineView: View {
    var body: some View {
        Label("Assistente Savoria", systemImage: "sparkle.magnifyingglass")
    }
}

// MARK: - Home Screen: Small

private struct AssistantSmallView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text("Assistente")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text("Toque para conversar")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Nutrition log widgets

private let nutritionLogMenuDeepLink = URL(string: "smartkitchen://foodlog")!

private struct FoodLogEntry: TimelineEntry {
    let date: Date
}

private struct FoodLogProvider: TimelineProvider {
    func placeholder(in context: Context) -> FoodLogEntry {
        FoodLogEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (FoodLogEntry) -> Void) {
        completion(FoodLogEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FoodLogEntry>) -> Void) {
        let now = Date()
        let next = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [FoodLogEntry(date: now)], policy: .after(next)))
    }
}

enum FoodLogWidgetAction: String, CaseIterable, Identifiable, Sendable {
    case menu
    case text
    case voice
    case camera
    case gallery
    case label
    case manual

    var id: String { rawValue }

    static let quickActions: [FoodLogWidgetAction] = [
        .text,
        .voice,
        .camera,
        .gallery,
        .label,
        .manual
    ]

    var url: URL {
        if self == .menu {
            return nutritionLogMenuDeepLink
        }

        return URL(string: "smartkitchen://foodlog/\(rawValue)")!
    }

    var systemImage: String {
        switch self {
        case .menu:    "fork.knife.circle.fill"
        case .text:    "character.cursor.ibeam"
        case .voice:   "waveform"
        case .camera:  "camera.fill"
        case .gallery: "photo.on.rectangle.angled"
        case .label:   "doc.text.viewfinder"
        case .manual:  "square.and.pencil"
        }
    }

    var title: String {
        switch self {
        case .menu:    String(localized: "Registrar Alimento")
        case .text:    String(localized: "Texto")
        case .voice:   String(localized: "Voz")
        case .camera:  String(localized: "Câmera")
        case .gallery: String(localized: "Galeria")
        case .label:   String(localized: "Rótulo")
        case .manual:  String(localized: "Registrar manualmente")
        }
    }

    var subtitle: String {
        switch self {
        case .menu:    String(localized: "Escolha o método")
        case .text:    String(localized: "Descreva a refeição")
        case .voice:   String(localized: "Registrar por voz")
        case .camera:  String(localized: "Registrar por foto")
        case .gallery: String(localized: "Registrar por foto")
        case .label:   String(localized: "Registrar por rótulo")
        case .manual:  String(localized: "Registrar manualmente")
        }
    }

    var configurationDisplayName: String {
        switch self {
        case .menu:    String(localized: "Registrar Alimento")
        case .text:    String(localized: "Registrar por texto")
        case .voice:   String(localized: "Registrar por voz")
        case .camera:  String(localized: "Câmera")
        case .gallery: String(localized: "Galeria")
        case .label:   String(localized: "Registrar por rótulo")
        case .manual:  String(localized: "Salvar alimento")
        }
    }
}

private enum FoodLogWidgetStyle {
    static let accent = Color(red: 0.18, green: 0.66, blue: 0.36)
    static let secondary = Color(red: 0.42, green: 0.84, blue: 0.58)
    static let warm = Color(red: 0.92, green: 0.70, blue: 0.22)
    static let darkBackground = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let lightBackground = Color.white

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [secondary, accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct FoodLogWidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? FoodLogWidgetStyle.darkBackground : FoodLogWidgetStyle.lightBackground)
            LinearGradient(
                colors: [
                    FoodLogWidgetStyle.secondary.opacity(colorScheme == .dark ? 0.18 : 0.16),
                    FoodLogWidgetStyle.accent.opacity(colorScheme == .dark ? 0.10 : 0.08),
                    FoodLogWidgetStyle.warm.opacity(colorScheme == .dark ? 0.10 : 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct FoodLogMenuWidget: Widget {
    let kind: String = "FoodLogMenuWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FoodLogProvider()) { entry in
            FoodLogMenuWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    FoodLogWidgetBackground()
                }
                .widgetURL(nutritionLogMenuDeepLink)
        }
        .configurationDisplayName(String(localized: "Registrar Alimento"))
        .description(String(localized: "Abra o Savoria para escolher texto, voz, câmera, galeria ou rótulo."))
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .systemSmall,
            .systemMedium,
        ])
    }
}

@MainActor
private func foodLogActionConfiguration(
    kind: String,
    action: FoodLogWidgetAction
) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FoodLogProvider()) { entry in
        FoodLogActionWidgetView(entry: entry, action: action)
            .containerBackground(for: .widget) {
                FoodLogWidgetBackground()
            }
            .widgetURL(action.url)
    }
    .configurationDisplayName(action.configurationDisplayName)
    .description(String(localized: "Abre o Savoria direto no fluxo escolhido para registrar alimento."))
    .supportedFamilies([
        .accessoryCircular,
        .accessoryRectangular,
        .accessoryInline,
        .systemSmall,
    ])
}

struct FoodLogTextWidget: Widget {
    let kind: String = "FoodLogTextWidget"

    var body: some WidgetConfiguration {
        foodLogActionConfiguration(kind: kind, action: .text)
    }
}

struct FoodLogVoiceWidget: Widget {
    let kind: String = "FoodLogVoiceWidget"

    var body: some WidgetConfiguration {
        foodLogActionConfiguration(kind: kind, action: .voice)
    }
}

struct FoodLogCameraWidget: Widget {
    let kind: String = "FoodLogCameraWidget"

    var body: some WidgetConfiguration {
        foodLogActionConfiguration(kind: kind, action: .camera)
    }
}

struct FoodLogGalleryWidget: Widget {
    let kind: String = "FoodLogGalleryWidget"

    var body: some WidgetConfiguration {
        foodLogActionConfiguration(kind: kind, action: .gallery)
    }
}

struct FoodLogLabelWidget: Widget {
    let kind: String = "FoodLogLabelWidget"

    var body: some WidgetConfiguration {
        foodLogActionConfiguration(kind: kind, action: .label)
    }
}

struct FoodLogManualWidget: Widget {
    let kind: String = "FoodLogManualWidget"

    var body: some WidgetConfiguration {
        foodLogActionConfiguration(kind: kind, action: .manual)
    }
}

private struct FoodLogMenuWidgetView: View {
    let entry: FoodLogEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            FoodLogCircularView(action: .menu)
        case .accessoryRectangular:
            FoodLogRectangularView(action: .menu)
        case .accessoryInline:
            FoodLogInlineView(action: .menu)
        case .systemMedium:
            FoodLogMediumMenuView()
        case .systemSmall:
            FoodLogSmallView(action: .menu)
        default:
            FoodLogSmallView(action: .menu)
        }
    }
}

private struct FoodLogActionWidgetView: View {
    let entry: FoodLogEntry
    let action: FoodLogWidgetAction
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            FoodLogCircularView(action: action)
        case .accessoryRectangular:
            FoodLogRectangularView(action: action)
        case .accessoryInline:
            FoodLogInlineView(action: action)
        case .systemSmall:
            FoodLogSmallView(action: action)
        default:
            FoodLogSmallView(action: action)
        }
    }
}

private struct FoodLogCircularView: View {
    let action: FoodLogWidgetAction

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: action.systemImage)
                .font(.system(size: action == .menu ? 27 : 24, weight: .semibold))
        }
        .widgetAccentable()
    }
}

private struct FoodLogRectangularView: View {
    let action: FoodLogWidgetAction

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: action.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(action.subtitle)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct FoodLogInlineView: View {
    let action: FoodLogWidgetAction

    var body: some View {
        Label {
            Text(action == .menu ? String(localized: "Abrir opções de registro") : action.title)
        } icon: {
            Image(systemName: action.systemImage)
        }
    }
}

private struct FoodLogSmallView: View {
    let action: FoodLogWidgetAction

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(FoodLogWidgetStyle.accentGradient)
                    .frame(width: 46, height: 46)
                Image(systemName: action.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(action.subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if action == .menu {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(FoodLogWidgetStyle.accent)
                    .padding(9)
                    .background(.primary.opacity(0.06), in: Circle())
            }
        }
    }
}

private struct FoodLogMediumMenuView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(FoodLogWidgetStyle.accentGradient)
                        .frame(width: 42, height: 42)
                    Image(systemName: FoodLogWidgetAction.menu.systemImage)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Registrar Alimento")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .lineLimit(2)
                    Text("Escolha como adicionar")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(width: 112, alignment: .leading)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(FoodLogWidgetAction.quickActions) { action in
                    Link(destination: action.url) {
                        FoodLogMediumActionButton(action: action)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct FoodLogMediumActionButton: View {
    let action: FoodLogWidgetAction

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: action.systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FoodLogWidgetStyle.accent)
                .frame(width: 17)
            Text(action.title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(.primary.opacity(0.055), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    AssistantWidget()
} timeline: {
    AssistantEntry(date: Date())
}

#Preview("Rectangular", as: .accessoryRectangular) {
    AssistantWidget()
} timeline: {
    AssistantEntry(date: Date())
}

#Preview("Inline", as: .accessoryInline) {
    AssistantWidget()
} timeline: {
    AssistantEntry(date: Date())
}

#Preview("Small", as: .systemSmall) {
    AssistantWidget()
} timeline: {
    AssistantEntry(date: Date())
}
