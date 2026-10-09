#if os(iOS)
import UIKit
import os

/// Opt-in, bounded main-run-loop evidence. Callback gaps are not GPU frame times.
/// No user content, model IDs, disk access or formatted logging per frame.
@MainActor
final class ActionTrace: NSObject {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-SavoriaActionTrace")
    static let shared = ActionTrace()
    private static let signposter = OSSignposter(subsystem: PerformanceLogger.subsystem, category: "ActionTrace")

    private struct Event: Codable {
        let sequence: Int
        let uptime: Double
        let page: String
        let phase: String
    }
    private struct Frame: Codable {
        let sequence: Int
        let uptime: Double
        let interval: Double
    }
    private struct Batch: Codable, Sendable {
        let events: [Event]
        let frames: [Frame]
    }
    private var sequence = 0
    private var page = "launch"
    private var events: [Event] = []
    private var frames: [Frame] = []
    private var lastFrame: Double?
    private var displayLink: CADisplayLink?
    private var stopTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    func install() {
        guard Self.enabled, observers.isEmpty else { return }
        events.reserveCapacity(256)
        frames.reserveCapacity(4096)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Self.shared.begin(page: Self.shared.page, phase: "foreground") }
        })
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Self.shared.mark(page: Self.shared.page, phase: "inactive")
                Self.shared.stopAndFlush()
            }
        })
        begin(page: "launch", phase: "launch")
    }

    func begin(page: String, phase: String = "handler") {
        guard Self.enabled else { return }
        sequence += 1
        self.page = page
        mark(page: page, phase: phase)
        if displayLink == nil {
            lastFrame = nil
            let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        stopTask?.cancel()
        stopTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.stopAndFlush()
        }
    }

    func mark(page: String, phase: String) {
        guard Self.enabled, events.count < 256 else { return }
        events.append(Event(sequence: sequence, uptime: ProcessInfo.processInfo.systemUptime, page: page, phase: phase))
        Self.signposter.emitEvent("action phase", "sequence=\(self.sequence) page=\(page, privacy: .public) phase=\(phase, privacy: .public)")
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = lastFrame, frames.count < 4096 {
            frames.append(Frame(sequence: sequence, uptime: now, interval: now - previous))
        }
        lastFrame = now
    }

    private func stopAndFlush() {
        displayLink?.invalidate()
        displayLink = nil
        stopTask?.cancel()
        stopTask = nil
        lastFrame = nil
        guard !events.isEmpty else { return }
        let batch = Batch(events: events, frames: frames)
        events.removeAll(keepingCapacity: true)
        frames.removeAll(keepingCapacity: true)
        // Capture URL before leaving the actor. Only reproducible diagnostics in Caches.
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ActionTraces", isDirectory: true)
        let filename = "trace-\(Int(ProcessInfo.processInfo.systemUptime * 1_000_000)).json"
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(batch)
                try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
            } catch {
                PerformanceLogger.error(.tabSwitch, "ActionTrace flush failed")
            }
        }
    }
}
#endif
