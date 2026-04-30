import SwiftUI

/// Botão discreto de "info" que mostra uma explicação curta em popover.
///
/// Usado ao lado de títulos de seções para manter o app limpo: em vez de
/// uma descrição longa fixa abaixo do título, a descrição vai para o
/// popover acessado por toque.
struct SectionInfoButton: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    @State private var isPresented = false

    init(title: LocalizedStringKey, message: LocalizedStringKey) {
        self.title = title
        self.message = message
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(4)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(message))
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .presentationCompactAdaptation(.popover)
        }
    }
}
