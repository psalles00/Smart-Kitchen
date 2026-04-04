#if os(iOS)
import SwiftUI
import UIKit

/// A tiny helper view that allows setting the status bar style from SwiftUI.
///
/// Usage:
///     .overlay(alignment: .top) {
///         StatusBarStyleView(style: .lightContent)
///             .frame(width: 0, height: 0)
///             .allowsHitTesting(false)
///     }
struct StatusBarStyleView: UIViewControllerRepresentable {
    /// The desired UIKit status bar style.
    let style: UIStatusBarStyle

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.style = style
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.style = style
    }

    /// An internal view controller that reports the preferredStatusBarStyle.
    final class Controller: UIViewController {
        var style: UIStatusBarStyle = .default {
            didSet { setNeedsStatusBarAppearanceUpdate() }
        }

        override var preferredStatusBarStyle: UIStatusBarStyle { style }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setNeedsStatusBarAppearanceUpdate()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            setNeedsStatusBarAppearanceUpdate()
        }
    }
}
#endif
