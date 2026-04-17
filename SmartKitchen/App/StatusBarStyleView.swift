#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Shared status bar style state

/// Global holder so that any `StatusBarStyleView` can publish the desired style
/// and the swizzled hosting controller reads it.
enum StatusBarStyleManager {
    nonisolated(unsafe) static var style: UIStatusBarStyle = .lightContent
}

// MARK: - UIHostingController swizzle

/// Swizzle `preferredStatusBarStyle` on the root hosting VC so the system
/// respects the value from StatusBarStyleManager.
enum StatusBarSwizzle {
    nonisolated(unsafe) static let install: Void = {
        let hostingClass: AnyClass = UIHostingController<AnyView>.self
        if let original = class_getInstanceMethod(
               hostingClass,
               #selector(getter: UIViewController.preferredStatusBarStyle)),
           let replacement = class_getInstanceMethod(
               StatusBarSwizzleHelper.self,
               #selector(getter: StatusBarSwizzleHelper.swizzled_preferredStatusBarStyle))
        {
            method_exchangeImplementations(original, replacement)
        }
    }()
}

private class StatusBarSwizzleHelper: UIViewController {
    @objc dynamic var swizzled_preferredStatusBarStyle: UIStatusBarStyle {
        StatusBarStyleManager.style
    }
}

// MARK: - SwiftUI helper view

/// A tiny helper view that allows setting the status bar style from SwiftUI.
///
/// Usage:
///     .overlay(alignment: .top) {
///         StatusBarStyleView(style: .lightContent)
///             .frame(width: 0, height: 0)
///             .allowsHitTesting(false)
///     }
struct StatusBarStyleView: UIViewControllerRepresentable {
    let style: UIStatusBarStyle

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.style = style
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.style = style
    }

    final class Controller: UIViewController {
        var style: UIStatusBarStyle = .default {
            didSet {
                StatusBarStyleManager.style = style
                // Walk up to the root to trigger a status bar refresh
                var vc: UIViewController? = self
                while let parent = vc?.parent { vc = parent }
                vc?.setNeedsStatusBarAppearanceUpdate()
            }
        }

        override var preferredStatusBarStyle: UIStatusBarStyle { style }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            StatusBarStyleManager.style = style
            var vc: UIViewController? = self
            while let parent = vc?.parent { vc = parent }
            vc?.setNeedsStatusBarAppearanceUpdate()
        }
    }
}
#endif
