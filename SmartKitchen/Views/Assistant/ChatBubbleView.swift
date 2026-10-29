import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Native indeterminate progress animates independently of network state changes.
/// It exists only while a response is pending, with no timer in the chat tree.
struct AssistantActivityIndicator: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 9) {
            if scenePhase == .active {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "ellipsis")
            }
            Text("Preparando resposta…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: .capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("assistant-response-activity")
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage
    let onQuickAction: (QuickAction) -> Void
    var hideQuickActions: Bool = false
    var contentFont: Font = .body
    var showsReportingAction: Bool = true

    private var isUser: Bool { message.role == .user }

    /// Splits long assistant messages into separate bubbles per paragraph for
    /// better visual organization. User messages are never split.
    private var paragraphs: [String] {
        let raw = message.content
        guard !isUser else { return [raw] }

        // Split on blank lines (one or more empty lines).
        let chunks = raw
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Only split when we actually have multiple paragraphs AND the
        // message is long enough that splitting visually helps.
        if chunks.count >= 2, raw.count > 280 {
            return chunks
        }
        return [raw]
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, chunk in
                    if isAssistantRule(chunk) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.24))
                            .frame(maxWidth: .infinity)
                            .frame(height: 1)
                            .padding(.vertical, 18)
                    } else {
                        bubbleText(chunk)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                isUser
                                    ? AnyShapeStyle(Color.accentColor)
                                    : AnyShapeStyle(Color(.secondarySystemBackground)),
                                in: bubbleShape
                            )
                            .foregroundStyle(isUser ? .white : .primary)
                    }
                }

                // Quick actions
                if !hideQuickActions, !message.quickActions.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(message.quickActions) { action in
                            Button {
                                onQuickAction(action)
                            } label: {
                                Text(action.label)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if showsReportingAction, message.role == .assistant, !message.content.isEmpty {
                    AssistantResponseReportButton(response: message.content)
                }
            }

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
    }

    private func isAssistantRule(_ content: String) -> Bool {
        !isUser && content.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
    }

    /// User messages stay as plain text (no markdown rendering, so anything
    /// the user wrote is preserved verbatim). Assistant messages render
    /// markdown via the `LocalizedStringKey` initializer.
    @ViewBuilder
    private func bubbleText(_ content: String) -> some View {
        if isUser {
            Text(content)
                .font(contentFont)
                .textSelection(.enabled)
        } else {
            Text(LocalizedStringKey(content))
                .font(contentFont)
                .textSelection(.enabled)
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        if isUser {
            UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 18,
                bottomTrailingRadius: 4, topTrailingRadius: 18
            )
        } else {
            UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 4,
                bottomTrailingRadius: 18, topTrailingRadius: 18
            )
        }
    }
}

struct AssistantResponseReportButton: View {
    let response: String
    @State private var showsReport = false

    var body: some View {
        Button {
            showsReport = true
        } label: {
            Label("Reportar resposta", systemImage: "flag")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assistant-report-response")
        .sheet(isPresented: $showsReport) {
            AssistantResponseReportView(response: response)
        }
    }
}

/// User-initiated report: no network request, transcript export, or automatic send.
enum AssistantResponseReport {
    static let email = "pedrosalles00@gmail.com"

    static func body(note: String, response: String, includeResponse: Bool) -> String {
        var parts = [String(localized: "Relato sobre uma resposta da IA do Savoria.")]
        let reason = String(note.prefix(1_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        if !reason.isEmpty { parts.append(reason) }
        if includeResponse {
            parts.append(String(localized: "Resposta selecionada:") + "\n" + String(response.prefix(2_000)))
        }
        return parts.joined(separator: "\n\n")
    }

    static func emailURL(body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: String(localized: "Reportar resposta — Savoria")),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}

struct AssistantResponseReportView: View {
    let response: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var note = ""
    @State private var includeResponse = false
    @State private var showsEmailFallback = false

    private var report: String {
        AssistantResponseReport.body(note: note, response: response, includeResponse: includeResponse)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Descreva um erro ou conteúdo inadequado. O relato será revisado pelo suporte. Nada é enviado até você confirmar o envio no seu app de e-mail.")
                        .font(.callout)
                    TextField("O que aconteceu?", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: note) { _, value in
                            if value.count > 1_000 { note = String(value.prefix(1_000)) }
                        }
                    Toggle("Incluir esta resposta no relato", isOn: $includeResponse)
                    Text("Confira se o texto contém informações pessoais antes de compartilhar. O histórico, fotos e dados da despensa não são anexados.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Prévia do relato") {
                    Text(report).textSelection(.enabled)
                    Text(AssistantResponseReport.email).foregroundStyle(.secondary)
                }
                Section {
                    Button("Abrir e-mail para o suporte") {
                        guard let url = AssistantResponseReport.emailURL(body: report) else {
                            showsEmailFallback = true
                            return
                        }
                        openURL(url) { accepted in showsEmailFallback = !accepted }
                    }
                    Button("Copiar relato") {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report, forType: .string)
                        #else
                        UIPasteboard.general.string = report
                        #endif
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Reportar resposta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .alert("Não foi possível abrir o e-mail", isPresented: $showsEmailFallback) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Copie o relato e envie para pedrosalles00@gmail.com pelo serviço de e-mail de sua preferência.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }
}

// MARK: - Simple Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let maxH = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += maxH + (i > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let maxH = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += maxH + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows = [[LayoutSubviews.Element]]()
        var currentRow = [LayoutSubviews.Element]()
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !currentRow.isEmpty && currentWidth + spacing + size.width > maxWidth {
                rows.append(currentRow)
                currentRow = [subview]
                currentWidth = size.width
            } else {
                currentRow.append(subview)
                currentWidth += (currentRow.count > 1 ? spacing : 0) + size.width
            }
        }
        if !currentRow.isEmpty { rows.append(currentRow) }
        return rows
    }
}

struct ExpandingFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let maxHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += maxHeight + (index > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widthProposal = ProposedViewSize(width: bounds.width, height: bounds.height)
        let rows = computeRows(proposal: widthProposal, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            let intrinsicSizes = row.map { $0.sizeThatFits(.unspecified) }
            let maxHeight = intrinsicSizes.map(\.height).max() ?? 0
            let totalIntrinsicWidth = intrinsicSizes.map(\.width).reduce(0, +)
            let totalSpacing = spacing * CGFloat(max(row.count - 1, 0))
            let extraWidth = max(0, bounds.width - totalIntrinsicWidth - totalSpacing)
            let extraPerItem = row.isEmpty ? 0 : extraWidth / CGFloat(row.count)

            var x = bounds.minX
            for (index, subview) in row.enumerated() {
                let size = intrinsicSizes[index]
                let expandedWidth = size.width + extraPerItem
                subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: expandedWidth, height: maxHeight)
                )
                x += expandedWidth + spacing
            }

            y += maxHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows = [[LayoutSubviews.Element]]()
        var currentRow = [LayoutSubviews.Element]()
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !currentRow.isEmpty && currentWidth + spacing + size.width > maxWidth {
                rows.append(currentRow)
                currentRow = [subview]
                currentWidth = size.width
            } else {
                currentRow.append(subview)
                currentWidth += (currentRow.count > 1 ? spacing : 0) + size.width
            }
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }
}
