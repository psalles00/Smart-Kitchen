import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Centralised performance / lifecycle logger.
///
/// All events are emitted through `os.Logger` (visible in Console.app and
/// `xcrun simctl spawn booted log show ... predicate 'subsystem ==
/// "com.pedrosalles.smartkitchen.perf"'`) and as `OSSignposter` intervals so
/// they show up in Instruments' "os_signpost" track for visual profiling of
/// foreground / cold-start jank.
///
/// Use ``PerformanceLogger/event(_:_:metadata:)`` for one-shot events and
/// ``PerformanceLogger/measure(_:_:metadata:_:)`` (sync) or
/// ``PerformanceLogger/measureAsync(_:_:metadata:_:)`` (async) to wrap
/// blocks of work. Each `measure*` call also prints the wall-clock duration
/// so it is easy to grep the log for slow steps without opening Instruments.
enum PerformanceLogger {
    static let subsystem = "com.pedrosalles.smartkitchen.perf"

    enum Category: String {
        case launch       = "Launch"
        case scenePhase   = "ScenePhase"
        case cloudSync    = "CloudSync"
        case dedup        = "Dedup"
        case dataSeeder   = "DataSeeder"
        case migration    = "Migration"
        case backup       = "Backup"
        case notifications = "Notifications"
        case subscriptions = "Subscriptions"
        case remoteChange  = "RemoteChange"

        var logger: Logger {
            Logger(subsystem: PerformanceLogger.subsystem, category: rawValue)
        }

        var signposter: OSSignposter {
            OSSignposter(subsystem: PerformanceLogger.subsystem, category: rawValue)
        }
    }

    // MARK: - One-shot events

    static func event(
        _ category: Category,
        _ message: @autoclosure () -> String,
        metadata: @autoclosure () -> String? = nil
    ) {
        let timestamp = monotonicMillisSinceLaunch()
        let meta = metadata()
        let body = meta.map { "\(message()) | \($0)" } ?? message()
        category.logger.notice("[+\(timestamp, format: .fixed(precision: 1))ms] \(body, privacy: .public)")
    }

    static func error(
        _ category: Category,
        _ message: @autoclosure () -> String,
        metadata: @autoclosure () -> String? = nil
    ) {
        let timestamp = monotonicMillisSinceLaunch()
        let meta = metadata()
        let body = meta.map { "\(message()) | \($0)" } ?? message()
        category.logger.error("[+\(timestamp, format: .fixed(precision: 1))ms] \(body, privacy: .public)")
    }

    // MARK: - Measured intervals (sync)

    @discardableResult
    static func measure<T>(
        _ category: Category,
        _ name: StaticString,
        metadata: @autoclosure () -> String? = nil,
        _ block: () throws -> T
    ) rethrows -> T {
        let signposter = category.signposter
        let state = signposter.beginInterval(name)
        let start = DispatchTime.now()
        defer {
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000.0
            signposter.endInterval(name, state)
            let metaSuffix = metadata().map { " | \($0)" } ?? ""
            category.logger.notice("⏱ \(name, privacy: .public) took \(elapsedMs, format: .fixed(precision: 1))ms\(metaSuffix, privacy: .public)")
        }
        return try block()
    }

    // MARK: - Process-wide timestamp anchor

    /// Set once when `SmartKitchenApp` is constructed so every subsequent log
    /// line carries a relative-to-launch timestamp. Useful to correlate
    /// CloudKit traffic with our own steps in a single timeline.
    private static let launchAnchor: DispatchTime = .now()
    /// Returns milliseconds since the first time the launcher imported this
    /// file. Cheap (monotonic clock), safe to call on any thread.
    static func monotonicMillisSinceLaunch() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds &- launchAnchor.uptimeNanoseconds) / 1_000_000.0
    }

    // MARK: - One-time configuration

    /// Wires up additional notification observers so we capture every
    /// lifecycle event the OS posts at us (not just the SwiftUI scene phase),
    /// plus the CloudKit `NSPersistentStoreRemoteChange` firehose. Call once
    /// from `SmartKitchenApp.init` after the app is up.
    static func installLifecycleObservers() {
        _ = lifecycleInstallToken
    }

    private static let lifecycleInstallToken: Void = {
        let center = NotificationCenter.default

        #if os(iOS)
        let lifecycleEvents: [(Notification.Name, String)] = [
            (UIApplication.didFinishLaunchingNotification, "didFinishLaunching"),
            (UIApplication.willEnterForegroundNotification, "willEnterForeground"),
            (UIApplication.didBecomeActiveNotification, "didBecomeActive"),
            (UIApplication.willResignActiveNotification, "willResignActive"),
            (UIApplication.didEnterBackgroundNotification, "didEnterBackground"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "protectedDataDidBecomeAvailable"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "protectedDataWillBecomeUnavailable"),
            (UIApplication.didReceiveMemoryWarningNotification, "didReceiveMemoryWarning"),
        ]
        #elseif os(macOS)
        let lifecycleEvents: [(Notification.Name, String)] = [
            (NSApplication.didFinishLaunchingNotification, "didFinishLaunching"),
            (NSApplication.willBecomeActiveNotification, "willBecomeActive"),
            (NSApplication.didBecomeActiveNotification, "didBecomeActive"),
            (NSApplication.willResignActiveNotification, "willResignActive"),
            (NSApplication.didResignActiveNotification, "didResignActive"),
            (NSApplication.willHideNotification, "willHide"),
            (NSApplication.didHideNotification, "didHide"),
            (NSApplication.willUnhideNotification, "willUnhide"),
            (NSApplication.didUnhideNotification, "didUnhide"),
        ]
        #endif

        for (name, label) in lifecycleEvents {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                event(.scenePhase, "lifecycle.\(label)")
            }
        }

        // CloudKit / SwiftData remote-change firehose. These notifications
        // arrive in bursts after foreground and are the primary trigger for
        // the deduplication pass that used to stall the main thread; logging
        // them with a relative timestamp makes the cause obvious in Console.
        center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { _ in
            event(.remoteChange, "NSPersistentStoreRemoteChange received")
        }    }()
}
