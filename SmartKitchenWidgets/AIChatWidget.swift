import WidgetKit
import SwiftUI

// MARK: - Deep link

/// `smartkitchen://aichat` → opens fullscreen assistant in AI chat mode,
/// keyboard focused, ready to type.
private let aiChatDeepLink = URL(string: "smartkitchen://aichat")!

// MARK: - Timeline

struct AIChatEntry: TimelineEntry {
    let date: Date
}

struct AIChatProvider: TimelineProvider {
    func placeholder(in context: Context) -> AIChatEntry {
        AIChatEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (AIChatEntry) -> Void) {
        completion(AIChatEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AIChatEntry>) -> Void) {
        let now = Date()
        let next = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [AIChatEntry(date: now)], policy: .after(next)))
    }
}

// MARK: - Widget

struct AIChatWidget: Widget {
    let kind: String = "AIChatWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AIChatProvider()) { entry in
            AIChatWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(aiChatDeepLink)
        }
        .configurationDisplayName("Modo IA")
        .description("Abre o Smart Kitchen direto no chat com a IA, com o teclado pronto para digitar.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .systemSmall,
        ])
    }
}

// MARK: - Root view

struct AIChatWidgetView: View {
    let entry: AIChatEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            AIChatCircularView()
        case .accessoryRectangular:
            AIChatRectangularView()
        case .accessoryInline:
            AIChatInlineView()
        case .systemSmall:
            AIChatSmallView()
        default:
            AIChatCircularView()
        }
    }
}

// MARK: - Lock Screen: Circular

private struct AIChatCircularView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "bubble.and.pencil")
                .font(.system(size: 26, weight: .semibold))
        }
        .widgetAccentable()
    }
}

// MARK: - Lock Screen: Rectangular

private struct AIChatRectangularView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.and.pencil")
                .font(.system(size: 24, weight: .semibold))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text("Modo IA")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .widgetAccentable()
                Text("Converse com a IA")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Lock Screen: Inline

private struct AIChatInlineView: View {
    var body: some View {
        Label("Modo IA Smart Kitchen", systemImage: "bubble.and.pencil")
    }
}

// MARK: - Home Screen: Small (1×1)

private struct AIChatSmallView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "bubble.and.pencil")
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
                Text("Modo IA")
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

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    AIChatWidget()
} timeline: {
    AIChatEntry(date: Date())
}

#Preview("Rectangular", as: .accessoryRectangular) {
    AIChatWidget()
} timeline: {
    AIChatEntry(date: Date())
}

#Preview("Inline", as: .accessoryInline) {
    AIChatWidget()
} timeline: {
    AIChatEntry(date: Date())
}

#Preview("Small", as: .systemSmall) {
    AIChatWidget()
} timeline: {
    AIChatEntry(date: Date())
}
