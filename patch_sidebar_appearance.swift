import SwiftUI

#if os(macOS)
struct DarkSidebarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DarkAppearanceView())
    }
}

private struct DarkAppearanceView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // Just force the superview representing the sidebar
            var parent = view.superview
            while parent != nil {
                if String(describing: type(of: parent!)).contains("Sidebar") || String(describing: type(of: parent!)).contains("SplitView") {
                    parent?.appearance = NSAppearance(named: .darkAqua)
                    break
                }
                parent = parent?.superview
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func forceDarkSidebar() -> some View {
        modifier(DarkSidebarModifier())
    }
}
#endif
