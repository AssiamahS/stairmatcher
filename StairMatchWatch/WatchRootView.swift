import SwiftUI

struct WatchRootView: View {
    private let wm = WorkoutManager.shared

    private var packColor: Color {
        switch wm.packState {
        case "behind": return .orange
        case "ahead": return .cyan
        case "withPack": return .green
        default: return .secondary
        }
    }
    private var packLabel: String {
        switch wm.packState {
        case "behind": return "BEHIND THE PACK"
        case "ahead": return "AHEAD"
        case "withPack": return "WITH THE PACK"
        default: return "SOLO"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(clock(wm.elapsed))
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text(packLabel)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(packColor)
            HStack(spacing: 14) {
                metric("heart.fill", wm.hr.map { "\(Int($0))" } ?? "—", .red)
                metric("figure.stairs", wm.spm.map { "\(Int($0))" } ?? "—", .green)
                metric("dial.medium", "L\(wm.level)", .orange)
            }
            .padding(.top, 2)
            Button(wm.running ? "End" : "Start") {
                if wm.running { wm.stop() } else { wm.start() }
            }
            .tint(wm.running ? .red : .green)
            .font(.headline)
            if wm.authDenied {
                Text("Allow Health access in Settings").font(.caption2).foregroundStyle(.orange)
            }
        }
        .task { await wm.requestAuth() }
    }

    private func metric(_ symbol: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.caption).foregroundStyle(color)
            Text(value).font(.system(.body, design: .rounded, weight: .bold)).monospacedDigit()
        }
    }

    private func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))   // seconds, not epoch ms — safe on arm64_32
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
