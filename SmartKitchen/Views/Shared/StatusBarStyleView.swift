import SwiftUI

#if os(iOS)
import UIKit

struct StatusBarStyleView: UIViewControllerRepresentable {
    let style: UIStatusBarStyle

    func makeUIViewController(context: Context) -> StatusBarStyleController {
        StatusBarStyleController(style: style)
    }

    func updateUIViewController(_ uiViewController: StatusBarStyleController, context: Context) {
        uiViewController.style = style
        uiViewController.refreshStatusBarAppearance()
    }
}

final class StatusBarStyleController: UIViewController {
    var style: UIStatusBarStyle

    init(style: UIStatusBarStyle) {
        self.style = style
        super.init(nibName: nil, bundle: nil)
        view.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        style
    }

    override var childForStatusBarStyle: UIViewController? {
        nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshStatusBarAppearance()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        refreshStatusBarAppearance()
    }

    func refreshStatusBarAppearance() {
        setNeedsStatusBarAppearanceUpdate()
        parent?.setNeedsStatusBarAppearanceUpdate()
        navigationController?.setNeedsStatusBarAppearanceUpdate()
        tabBarController?.setNeedsStatusBarAppearanceUpdate()
    }
}
#endif
