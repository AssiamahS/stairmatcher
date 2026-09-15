import SwiftUI

extension View {
    func card() -> some View {
        self
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var source: MetricSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let source { SourceBadge(source: source) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Tiny provenance tag so an estimate never looks like machine truth.
struct SourceBadge: View {
    var source: MetricSource

    private var label: String {
        switch source {
        case .pedometer: return "watch"
        case .watchHR: return "watch"
        case .manual: return "you"
        case .estimated: return "est."
        case .ftms: return "machine"
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(source == .estimated ? Color.orange.opacity(0.25) : Color.green.opacity(0.25), in: Capsule())
            .foregroundStyle(source == .estimated ? .orange : .green)
    }
}

enum Fmt {
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    static func int(_ v: Double?) -> String {
        guard let v else { return "—" }
        return Int(v.rounded()).formatted()
    }
}

struct ClimberCard: View {
    var climber: Climber
    var isYou = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(isYou ? "You" : climber.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if climber.finished {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
            Text(climber.where_)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider().overlay(Color.white.opacity(0.1))
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.clock(climber.elapsed))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("\(Fmt.int(climber.metrics.steps?.v)) steps")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        if let s = climber.metrics.steps?.src { SourceBadge(source: s) }
                    }
                    Text("Level \(Fmt.int(climber.metrics.level?.v))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isYou ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isYou ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
        )
    }
}
