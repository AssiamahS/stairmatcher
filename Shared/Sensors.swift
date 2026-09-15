import Foundation
import CoreMotion
import WatchConnectivity

extension CMPedometer {
    /// Live steps + cadence since `from`, delivered on the main actor. Shared by the
    /// phone (fallback source) and the watch (primary source).
    func startSessionUpdates(from: Date, onUpdate: @escaping @MainActor (_ steps: Double, _ spm: Double?) -> Void) {
        guard CMPedometer.isStepCountingAvailable() else { return }
        startUpdates(from: from) { data, _ in
            guard let data else { return }
            let steps = data.numberOfSteps.doubleValue
            let spm = data.currentCadence.map { $0.doubleValue * 60 }
            Task { @MainActor in onUpdate(steps, spm) }
        }
    }
}

extension WCSession {
    /// Interactive message when the counterpart is reachable, application context otherwise,
    /// and context as the fallback if the message fails in flight.
    func sendOrQueue(_ payload: [String: Any]) {
        if isReachable {
            sendMessage(payload, replyHandler: nil) { [self] _ in try? updateApplicationContext(payload) }
        } else {
            try? updateApplicationContext(payload)
        }
    }
}
