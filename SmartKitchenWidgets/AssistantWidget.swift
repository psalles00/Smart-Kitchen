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
        .description("Abre o Smart Kitchen direto na conversa com o assistente, com o teclado pronto.")
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
        Label("Assistente Smart Kitchen", systemImage: "sparkle.magnifyingglass")
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
