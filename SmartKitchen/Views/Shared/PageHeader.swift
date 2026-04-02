import SwiftUI

struct PageHeader: View {
    let title: String
    let isInverted: Bool
    var trailingContent: (() -> AnyView)? = nil

    private var textColor: Color {
        isInverted ? .primary : .white
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.pageTitle)
                .foregroundColor(textColor)

            Spacer()

            if let trailing = trailingContent {
                trailing()
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
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
