import SwiftUI

struct SummaryView: View {
    @Environment(SessionEngine.self) private var engine

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = engine.summary {
                    VStack(spacing: 14) {
                        VStack(spacing: 6) {
                            Text(s.rank.map { "#\($0) of \(s.packSize)" } ?? "Climb complete")
                                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                            Text(Fmt.clock(s.elapsed))
                                .font(.system(size: 44, weight: .heavy, design: .rounded)).monospacedDigit()
                            Text(s.packSize > 1 ? "You climbed with \(s.packSize - 1) other\(s.packSize == 2 ? "" : "s")" : "Solo climb — next time someone joins you")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .card()

                        HStack(spacing: 10) {
                            StatTile(title: "Steps", value: Fmt.int(s.metrics.steps?.v), source: s.metrics.steps?.src)
                            StatTile(title: "Floors", value: Fmt.int(s.metrics.floors?.v), source: s.metrics.floors?.src)
                        }
                        HStack(spacing: 10) {
                            StatTile(title: "Avg level", value: Fmt.int(s.metrics.level?.v), source: s.metrics.level?.src)
                            StatTile(title: "kcal", value: Fmt.int(s.metrics.kcal?.v), source: s.metrics.kcal?.src)
                        }

                        finisherWall(s)
                        legend
                    }
                    .padding(16)
                }
            }
            .background(Color(red: 0.039, green: 0.043, blue: 0.055).ignoresSafeArea())
            .navigationTitle("Summary")
            .safeAreaInset(edge: .bottom) {
                Button { engine.reset() } label: {
                    Text("DONE").font(.system(.headline, design: .rounded, weight: .black)).tracking(1)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(16)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func finisherWall(_ s: SessionSummary) -> some View {
        let live = engine.client.snapshot?.climbers.filter(\.finished) ?? s.finishers
        return VStack(alignment: .leading, spacing: 8) {
            Text("FINISHER WALL").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
            ForEach(live.sorted { ($0.finishedAt ?? 0) < ($1.finishedAt ?? 0) }) { c in
                HStack {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text(c.id == engine.identity.installId ? "You" : c.name).font(.subheadline.weight(.semibold))
                    Text(c.where_).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Fmt.clock(c.elapsed)) · \(Fmt.int(c.metrics.steps?.v)) steps").font(.caption.monospacedDigit())
                }
            }
        }
        .card()
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHERE THE NUMBERS COME FROM").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
            HStack(spacing: 6) { SourceBadge(source: .pedometer); Text("Apple Watch or iPhone motion sensor").font(.caption) }
            HStack(spacing: 6) { SourceBadge(source: .manual); Text("The level you set").font(.caption) }
            HStack(spacing: 6) { SourceBadge(source: .estimated); Text("Modelled from level and time (\(StairModel.name)). Not the console's number.").font(.caption) }
        }
        .foregroundStyle(.secondary)
        .card()
    }
}
