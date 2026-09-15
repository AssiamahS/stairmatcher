import Foundation
import CoreMotion
import Observation

enum PackState: String {
    case solo, withPack, behind, ahead

    var label: String {
        switch self {
        case .solo: return "Climbing solo — others can join you"
        case .withPack: return "With the pack"
        case .behind: return "You dropped off the pack"
        case .ahead: return "You're pulling ahead"
        }
    }
}

struct SessionSummary: Equatable {
    var mode: RoomMode
    var elapsed: Double
    var metrics: Metrics
    var finishers: [Climber]
    var packSize: Int
    var rank: Int?
}

/// One climb: joins a room, assembles telemetry from the best available source every
/// second, ships it every 5 seconds, and watches the pack.
@MainActor
@Observable
final class SessionEngine {
    enum Phase: Equatable { case idle, joining, climbing, finished }

    var phase: Phase = .idle
    var mode: RoomMode = .pack
    var level: Int = 6 {
        didSet {
            level = min(max(level, StairModel.levelRange.lowerBound), StairModel.levelRange.upperBound)
            UserDefaults.standard.set(level, forKey: "level")
            if phase == .climbing { watch.packState(packState.rawValue, level: level) }
        }
    }
    var elapsed: Double = 0
    var metrics = Metrics()
    var packState: PackState = .solo
    var summary: SessionSummary?
    var joinError: String?

    let client = LiveClient()
    let watch = WatchBridge.shared
    let identity = Identity.shared

    private let pedometer = CMPedometer()
    private var startedAt: Date?
    private var phoneSteps: Double?
    private var phoneCadence: Double?
    private var estimatedSteps: Double = 0
    private var lastTick: Date?
    private var lastSend: Date = .distantPast
    private var lastHaptic: Date = .distantPast
    private var ticker: Task<Void, Never>?

    init() {
        level = UserDefaults.standard.object(forKey: "level") as? Int ?? 6
    }

    // MARK: Lifecycle

    func start(mode: RoomMode) async {
        guard phase == .idle else { return }
        self.mode = mode
        phase = .joining
        joinError = nil
        do {
            let roomId = try await client.join(mode: mode)
            client.connect(roomId: roomId, id: identity.installId, name: identity.name, city: identity.publicCity)
        } catch {
            joinError = "Couldn't reach the network: \(error.localizedDescription)"
            phase = .idle
            return
        }
        let now = Date()
        startedAt = now
        lastTick = now
        elapsed = 0
        estimatedSteps = 0
        metrics = Metrics()
        packState = .solo
        watch.clear()
        watch.startWatch(level: level)
        startPhonePedometer(from: now)
        phase = .climbing
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    func finish() {
        guard phase == .climbing else { return }
        tick(force: true)
        client.finish()
        watch.stopWatch()
        pedometer.stopUpdates()
        ticker?.cancel()
        let snap = client.snapshot
        let finishers = (snap?.climbers ?? []).filter(\.finished)
        var rank: Int?
        if mode == .race, let snap, let you = client.youId {
            let sorted = snap.climbers.sorted { ($0.metrics.steps?.v ?? 0) > ($1.metrics.steps?.v ?? 0) }
            rank = sorted.firstIndex { $0.id == you }.map { $0 + 1 }
        }
        summary = SessionSummary(mode: mode, elapsed: elapsed, metrics: metrics, finishers: finishers,
                                 packSize: snap?.pack.size ?? 1, rank: rank)
        phase = .finished
        // Keep the socket open a few seconds so the finisher wall can show us.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.client.disconnect()
        }
    }

    func reset() {
        ticker?.cancel()
        client.disconnect()
        pedometer.stopUpdates()
        watch.clear()
        summary = nil
        phase = .idle
    }

    // MARK: Telemetry

    private func startPhonePedometer(from: Date) {
        phoneSteps = nil
        phoneCadence = nil
        pedometer.startSessionUpdates(from: from) { [weak self] steps, spm in
            self?.phoneSteps = steps
            self?.phoneCadence = spm
        }
    }

    private func tick(force: Bool = false) {
        guard phase == .climbing, let startedAt else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastTick ?? now)
        lastTick = now
        elapsed = now.timeIntervalSince(startedAt)
        metrics = assemble(dt: dt)
        evaluatePack()
        if force || now.timeIntervalSince(lastSend) >= 5 {
            lastSend = now
            client.sendTelemetry(elapsed: elapsed, metrics: metrics)
        }
    }

    /// Best source wins, and the loser's provenance is never faked.
    private func assemble(dt: Double) -> Metrics {
        var m = Metrics()
        m.level = Metric(Double(level), .manual)

        // cadence
        if watch.isLive, let s = watch.spm {
            m.spm = Metric(s, .pedometer)
        } else if let c = phoneCadence {
            m.spm = Metric(c, .pedometer)
        } else {
            m.spm = Metric(StairModel.spm(level: level), .estimated, model: StairModel.name)
        }

        // steps
        estimatedSteps += (m.spm?.v ?? 0) / 60 * dt
        if watch.isLive, let s = watch.steps {
            m.steps = Metric(s, .pedometer)
        } else if let s = phoneSteps, s > 0 {
            m.steps = Metric(s, .pedometer)
        } else {
            m.steps = Metric(estimatedSteps.rounded(), .estimated, model: StairModel.name)
        }

        if watch.isLive, let hr = watch.hr { m.hr = Metric(hr, .watchHR) }
        m.effort = EffortScore.compute(hr: m.hr?.v, spm: m.spm?.v, age: identity.age)
        let steps = m.steps?.v ?? 0
        m.floors = Metric(StairModel.floors(steps: steps).rounded(.down), .estimated, model: StairModel.name)
        m.kcal = Metric(StairModel.kcal(steps: steps, weightKg: identity.weightKg).rounded(), .estimated, model: StairModel.name)
        return m
    }

    private func evaluatePack() {
        guard let snap = client.snapshot else { packState = .solo; return }
        let others = snap.climbers.filter { !$0.finished && $0.id != client.youId }
        guard !others.isEmpty, let mine = metrics.spm?.v else { packState = .solo; return }
        let theirs = others.compactMap { $0.metrics.spm?.v }
        guard !theirs.isEmpty else { packState = .solo; return }
        let avg = theirs.reduce(0, +) / Double(theirs.count)
        let ratio = avg > 0 ? mine / avg : 1
        let next: PackState = ratio < 0.85 ? .behind : (ratio > 1.15 ? .ahead : .withPack)
        if next != packState {
            packState = next
            watch.packState(next.rawValue, level: level)
            if next == .behind, Date().timeIntervalSince(lastHaptic) > 60 {
                lastHaptic = .now
                watch.haptic("behind", packState: next.rawValue)
            }
        }
    }
}
