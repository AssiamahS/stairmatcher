import Foundation
import WatchConnectivity
import Observation

/// Phone side of the watch link. The watch owns the sensors (heart rate, cadence);
/// the phone owns the session and tells the watch when to start, stop and buzz.
@MainActor
@Observable
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    var hr: Double?
    var spm: Double?
    var steps: Double?
    var watchElapsed: Double?
    var watchRunning = false
    var reachable = false
    var lastUpdate: Date?

    /// Fresh enough to trust as the live source.
    var isLive: Bool {
        guard let lastUpdate else { return false }
        return Date().timeIntervalSince(lastUpdate) < 15
    }

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(command: String, extra: [String: Any] = [:]) {
        guard WCSession.isSupported() else { return }
        var payload = extra
        payload[WatchKeys.command] = command
        WCSession.default.sendOrQueue(payload)
    }

    func startWatch(level: Int) { send(command: "start", extra: [WatchKeys.level: level]) }
    func stopWatch() { send(command: "stop") }
    func haptic(_ kind: String, packState: String) {
        send(command: "haptic", extra: [WatchKeys.haptic: kind, WatchKeys.packState: packState])
    }
    func packState(_ label: String, level: Int) {
        send(command: "state", extra: [WatchKeys.packState: label, WatchKeys.level: level])
    }

    func clear() {
        hr = nil; spm = nil; steps = nil; watchElapsed = nil; watchRunning = false; lastUpdate = nil
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let r = session.isReachable
        Task { @MainActor in self.reachable = r }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let r = session.isReachable
        Task { @MainActor in self.reachable = r }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.apply(context) }
    }

    private func apply(_ m: [String: Any]) {
        if let v = m[WatchKeys.hr] as? Double { hr = v > 0 ? v : nil }
        if let v = m[WatchKeys.spm] as? Double { spm = v }
        if let v = m[WatchKeys.steps] as? Double { steps = v }
        if let v = m[WatchKeys.elapsed] as? Double { watchElapsed = v }
        if let v = m[WatchKeys.running] as? Bool { watchRunning = v }
        lastUpdate = .now
    }
}
