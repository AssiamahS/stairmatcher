import Foundation

/// Where a number came from. A phone cannot read a StairMaster's console, so every
/// metric carries its provenance and the relay keeps it. "estimated" values are
/// derived from a named model and are never presented as machine truth.
enum MetricSource: String, Codable, CaseIterable {
    case pedometer   // Core Motion step counter (watch or phone)
    case watchHR = "watch_hr"
    case manual      // user typed it (machine level)
    case estimated   // derived from a model, see `model`
    case ftms        // Bluetooth Fitness Machine Service, future
}

struct Metric: Codable, Equatable {
    var v: Double
    var src: MetricSource
    var model: String?

    init(_ v: Double, _ src: MetricSource, model: String? = nil) {
        self.v = v
        self.src = src
        self.model = model
    }
}

/// The metric bag sent every few seconds. Keys mirror the relay's METRIC_KEYS.
struct Metrics: Codable, Equatable {
    var steps: Metric?
    var spm: Metric?
    var level: Metric?
    var hr: Metric?
    var effort: Metric?
    var floors: Metric?
    var kcal: Metric?

    subscript(key: String) -> Metric? {
        switch key {
        case "steps": return steps
        case "spm": return spm
        case "level": return level
        case "hr": return hr
        case "effort": return effort
        case "floors": return floors
        case "kcal": return kcal
        default: return nil
        }
    }
}

/// Generic StairMaster telemetry model. Level → steps per minute is roughly linear on
/// the 8-series consoles (level 1 ≈ 24 spm, level 20 ≈ 162 spm). Other machines differ,
/// which is exactly why estimates are tagged with this model name.
enum StairModel {
    static let name = "stairmaster-generic-v1"
    static let levelRange = 1...20
    static let stepsPerFloor = 16.0

    static func spm(level: Int) -> Double {
        let l = Double(min(max(level, levelRange.lowerBound), levelRange.upperBound))
        return 24 + (l - 1) * 7.26
    }

    static func floors(steps: Double) -> Double { steps / stepsPerFloor }

    /// Rough energy model: ~0.17 kcal per step at 75 kg, scaled by weight.
    static func kcal(steps: Double, weightKg: Double) -> Double {
        steps * 0.17 * (weightKg / 75)
    }
}

/// How hard someone is working, 0–100, blended so a level 6 beginner and a level 12
/// athlete land in the same pack honestly.
enum EffortScore {
    static func maxHR(age: Int) -> Double { 220 - Double(age) }

    static func compute(hr: Double?, spm: Double?, age: Int) -> Metric? {
        let cadencePct = spm.map { min(max($0 / 120, 0), 1) }
        if let hr, hr > 0 {
            let rest = 60.0
            let hrPct = min(max((hr - rest) / (maxHR(age: age) - rest), 0), 1)
            let blended = 0.6 * hrPct + 0.4 * (cadencePct ?? hrPct)
            return Metric((blended * 100).rounded(), .watchHR)
        }
        if let cadencePct {
            return Metric((cadencePct * 100).rounded(), .estimated, model: "cadence-only")
        }
        return nil
    }
}
