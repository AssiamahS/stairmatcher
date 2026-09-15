import Foundation

/// Wire format shared with the relay (worker/src/index.js).
enum RoomMode: String, Codable, CaseIterable, Identifiable {
    case pack, race
    var id: String { rawValue }
    var title: String { self == .pack ? "Pack" : "Race" }
    var blurb: String {
        self == .pack ? "Move as one. Hold the pack's pace." : "Live leaderboard. Most steps wins."
    }
}

struct Climber: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var city: String?
    var elapsed: Double
    var metrics: Metrics
    var finished: Bool
    var finishedAt: Double?
    var roomId: String?
    var mode: RoomMode?

    var where_: String { city ?? "Somewhere" }
}

struct PackStats: Codable, Equatable {
    var size: Int
    var avgSpm: Double?
    var avgEffort: Double?
    var avgLevel: Double?
}

struct RoomInfo: Codable, Equatable {
    var id: String
    var mode: RoomMode
    var startedAt: Double
}

struct RoomSnapshot: Codable, Equatable {
    var room: RoomInfo
    var climbers: [Climber]
    var pack: PackStats
    var now: Double
}

struct LiveBoard: Codable, Equatable {
    struct Room: Codable, Equatable, Identifiable {
        var id: String
        var mode: RoomMode
        var count: Int
        var startedAt: Double
        var pack: PackStats?
    }
    var now: Double
    var climbing: Int
    var rooms: [Room]
    var climbers: [Climber]

    static let empty = LiveBoard(now: 0, climbing: 0, rooms: [], climbers: [])
}

/// Server → client envelope. Only `type` is guaranteed; decode the rest per type.
struct ServerEnvelope: Decodable {
    var type: String
    var you: String?
    var from: String?
    var text: String?
}

struct TelemetryMessage: Encodable {
    var type = "telemetry"
    var elapsed: Double
    var metrics: Metrics
}

/// Watch ↔ phone message keys (WCSession).
enum WatchKeys {
    static let hr = "hr"                 // Double bpm
    static let spm = "spm"               // Double steps/min
    static let steps = "steps"           // Double steps since session start
    static let elapsed = "elapsed"       // Double seconds since watch session start
    static let running = "running"       // Bool
    static let command = "cmd"           // String: start | stop | haptic
    static let haptic = "haptic"         // String: behind | ahead | joined | finish
    static let packState = "pack"        // String label for the watch UI
    static let level = "level"           // Int
}

enum RelayConfig {
    /// Override with `defaults write com.assiamah.stairmatcher relayURL https://…` while testing.
    static var baseURL: URL {
        if let s = UserDefaults.standard.string(forKey: "relayURL"), let u = URL(string: s) { return u }
        return URL(string: "https://stairmatch.sylvesterassiamahpm.workers.dev")!
    }
}
