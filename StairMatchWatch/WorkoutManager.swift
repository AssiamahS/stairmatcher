import Foundation
import HealthKit
import CoreMotion
import WatchConnectivity
import WatchKit
import Observation

/// The watch owns the sensors. It runs a Stair Stepper workout (so the climb lands
/// in Health), reads heart rate from the live builder, cadence and steps from the
/// pedometer, and streams them to the phone every 3 seconds. The phone owns the
/// session and tells the watch when to start, stop and buzz.
@MainActor
@Observable
final class WorkoutManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, WCSessionDelegate {
    static let shared = WorkoutManager()

    var running = false
    var hr: Double?
    var spm: Double?
    var steps: Double = 0
    var elapsed: Double = 0
    var packState = "solo"
    var level = 6
    var phoneReachable = false
    var authDenied = false

    private let health = HKHealthStore()
    private let pedometer = CMPedometer()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startedAt: Date?
    private var ticker: Task<Void, Never>?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: Control

    func requestAuth() async {
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKQuantityType(.stepCount)]
        let share: Set<HKSampleType> = [HKQuantityType.workoutType()]
        do { try await health.requestAuthorization(toShare: share, read: read) } catch { authDenied = true }
    }

    func start() {
        guard !running else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .stairClimbing
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: health, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: config)
            s.delegate = self
            b.delegate = self
            session = s
            builder = b
            let now = Date()
            startedAt = now
            s.startActivity(with: now)
            b.beginCollection(withStart: now) { _, _ in }
            startPedometer(from: now)
            running = true
            steps = 0
            elapsed = 0
            WKInterfaceDevice.current().play(.start)
            ticker?.cancel()
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    self?.tick()
                }
            }
        } catch {
            authDenied = true
        }
    }

    func stop() {
        guard running else { return }
        running = false
        ticker?.cancel()
        pedometer.stopUpdates()
        session?.end()
        let b = builder
        b?.endCollection(withEnd: .now) { _, _ in
            b?.finishWorkout { _, _ in }
        }
        WKInterfaceDevice.current().play(.stop)
        tick()
        session = nil
        builder = nil
    }

    private func startPedometer(from: Date) {
        pedometer.startSessionUpdates(from: from) { [weak self] steps, spm in
            self?.steps = steps
            if let spm { self?.spm = spm }
        }
    }

    private func tick() {
        if let startedAt { elapsed = Date().timeIntervalSince(startedAt) }
        guard WCSession.isSupported() else { return }
        let payload: [String: Any] = [
            WatchKeys.hr: hr ?? 0,
            WatchKeys.spm: spm ?? 0,
            WatchKeys.steps: steps,
            WatchKeys.elapsed: elapsed,
            WatchKeys.running: running,
        ]
        WCSession.default.sendOrQueue(payload)
    }

    private func handle(_ m: [String: Any]) {
        if let l = m[WatchKeys.level] as? Int { level = l }
        if let p = m[WatchKeys.packState] as? String { packState = p }
        switch m[WatchKeys.command] as? String {
        case "start": start()
        case "stop": stop()
        case "haptic":
            switch m[WatchKeys.haptic] as? String {
            case "behind": WKInterfaceDevice.current().play(.directionDown)
            case "ahead": WKInterfaceDevice.current().play(.directionUp)
            case "finish": WKInterfaceDevice.current().play(.success)
            default: WKInterfaceDevice.current().play(.notification)
            }
        default: break
        }
    }

    // MARK: HKWorkoutSessionDelegate

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.running = false }
    }

    // MARK: HKLiveWorkoutBuilderDelegate

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType),
              let bpm = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())) else { return }
        Task { @MainActor in self.hr = bpm }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let r = session.isReachable
        Task { @MainActor in self.phoneReachable = r }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let r = session.isReachable
        Task { @MainActor in self.phoneReachable = r }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handle(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.handle(applicationContext) }
    }
}
