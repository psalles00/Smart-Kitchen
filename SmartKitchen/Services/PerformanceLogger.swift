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
/// ``PerformanceLogger/measure(_:_:metadata:_:)`` to wrap synchronous blocks
/// of work. Each measurement also prints the wall-clock duration so it is
/// easy to grep the log for slow steps without opening Instruments.
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
    private static let launchAnchorUptime = ProcessInfo.processInfo.systemUptime
    /// Returns milliseconds since the first time the launcher imported this
    /// file. Cheap (monotonic clock), safe to call on any thread.
    static func monotonicMillisSinceLaunch() -> Double {
        max(0, (ProcessInfo.processInfo.systemUptime - launchAnchorUptime) * 1_000.0)
    }

    // MARK: - One-time configuration

    /// Wires up additional notification observers so we capture every
    /// lifecycle event the OS posts at us (not just the SwiftUI scene phase).
    /// Call once from `SmartKitchenApp.init` after the app is up.
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
    }()

    // MARK: - Main-thread hang detector
    //
    // A small watchdog that periodically pings the main thread from a
    // background queue. If the main thread does not service the ping within
    // `threshold` seconds we consider it hung and log a hang event. When the
    // ping is finally serviced we log the total hang duration. This is the
    // only reliable way to attribute the "freeze on resume" the user sees to
    // an actual main-thread stall (CloudKit merge, SwiftData @Query refresh,
    // SwiftUI body re-evaluation, etc.) versus a rendering pipeline issue.

    private static let hangStateLock = NSLock()
    nonisolated(unsafe) private static var hangLastHeartbeat: TimeInterval = ProcessInfo.processInfo.systemUptime
    nonisolated(unsafe) private static var hangActive: Bool = false
    nonisolated(unsafe) private static var hangStartedAt: TimeInterval = 0
    nonisolated(unsafe) private static var hangDetectorTimer: DispatchSourceTimer?

    /// Installs a watchdog that logs whenever the main thread is unresponsive
    /// for more than `thresholdMs`. Safe to call multiple times — installs
    /// only on the first call. Cheap (one async per `pollIntervalMs` to main
    /// plus a timer tick on a utility queue).
    static func installMainThreadHangDetector(thresholdMs: Int = 200, pollIntervalMs: Int = 100) {
        hangStateLock.lock()
        let already = hangDetectorTimer != nil
        hangStateLock.unlock()
        guard !already else { return }

        let queue = DispatchQueue(label: "com.pedrosalles.smartkitchen.perf.hangdetector", qos: .userInitiated)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = DispatchTimeInterval.milliseconds(pollIntervalMs)
        let threshold = TimeInterval(thresholdMs) / 1_000.0
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(20))
        timer.setEventHandler {
            // Schedule a heartbeat update on main. When this block runs we
            // know main was responsive at that instant.
            DispatchQueue.main.async {
                let now = ProcessInfo.processInfo.systemUptime
                var endedHangDurationMs: Int? = nil
                hangStateLock.lock()
                let wasActive = hangActive
                if wasActive {
                    endedHangDurationMs = Int((now - hangStartedAt) * 1_000.0)
                    hangActive = false
                }
                hangLastHeartbeat = now
                hangStateLock.unlock()
                if let durationMs = endedHangDurationMs {
                    event(.scenePhase, "main thread hang ended", metadata: "durationMs=\(durationMs)")
                }
            }

            // Then check from the background queue how stale main is.
            let now = ProcessInfo.processInfo.systemUptime
            hangStateLock.lock()
            let lag = now - hangLastHeartbeat
            let shouldOpen = !hangActive && lag > threshold
            if shouldOpen {
                hangActive = true
                hangStartedAt = hangLastHeartbeat
            }
            hangStateLock.unlock()
            if shouldOpen {
                event(.scenePhase, "main thread hang detected", metadata: "lagMs=\(Int(lag * 1_000.0))")
            }
        }
        timer.resume()
        hangStateLock.lock()
        hangDetectorTimer = timer
        hangStateLock.unlock()
    }
}
