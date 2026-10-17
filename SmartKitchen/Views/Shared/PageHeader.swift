import SwiftUI

enum PageHeaderPalette {
    static let control = Color(white: 174 / 255.0)
    static var title: LinearGradient {
        LinearGradient(colors: [.white, control], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct PageHeaderControlsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var usesPageHeaderControls: Bool {
        get { self[PageHeaderControlsKey.self] }
        set { self[PageHeaderControlsKey.self] = newValue }
    }
}

struct PageHeaderDescriptionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
            .lineLimit(3)
            .minimumScaleFactor(0.82)
            .allowsTightening(true)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PageHeader: View {
    let title: String
    let isInverted: Bool
    var trailingContent: (() -> AnyView)? = nil

    var body: some View {
        HStack(alignment: .center) {
            #if os(iOS)
            if title == "Savoria" {
                Text(title)
                    .font(.custom("Bricolage Grotesque", size: 44, relativeTo: .largeTitle).bold())
                    .foregroundStyle(PageHeaderPalette.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            } else {
                Text(title).font(.pageTitle).foregroundStyle(PageHeaderPalette.title)
            }
            #else
            Text(title).font(.pageTitle).foregroundStyle(PageHeaderPalette.title)
            #endif

            Spacer()

            if let trailing = trailingContent {
                trailing()
                    .environment(\.usesPageHeaderControls, true)
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
            }
        }
        .padding(.horizontal)
        #if os(macOS)
        .padding(.top, 0)
        #else
        .padding(.top, 8)
        #endif
    }
}

extension PageHeader {
    init(
        title: String,
        isInverted: Bool,
        @ViewBuilder trailing: @escaping () -> some View
    ) {
        self.title = title
        self.isInverted = isInverted
        self.trailingContent = { AnyView(trailing()) }
    }
}
