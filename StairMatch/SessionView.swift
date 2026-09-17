import SwiftUI

struct SessionView: View {
    @Environment(SessionEngine.self) private var engine
    @State private var confirmFinish = false

    private var client: LiveClient { engine.client }
    private var snap: RoomSnapshot? { client.snapshot }
    private var others: [Climber] { (snap?.climbers ?? []).filter { $0.id != engine.identity.installId } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    clock
                    packBanner
                    myStats
                    levelControl
                    if engine.mode == .pack { packRail } else { leaderboard }
                    cheers
                }
                .padding(16)
                .padding(.bottom, 110)
            }
            .background(Color(red: 0.039, green: 0.043, blue: 0.055).ignoresSafeArea())
            .navigationTitle(engine.mode == .pack ? "The Pack" : "Race")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .confirmationDialog("Finish this climb?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish", role: .destructive) { engine.finish() }
                Button("Keep climbing", role: .cancel) {}
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var clock: some View {
        VStack(spacing: 4) {
            Text(Fmt.clock(engine.elapsed))
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                Circle().fill(client.connected ? .green : .orange).frame(width: 8, height: 8)
                Text(client.connected ? "\(snap?.pack.size ?? 1) in your room" : "Reconnecting…")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
    }

    private var packBanner: some View {
        let state = engine.packState
        let color: Color = state == .behind ? .orange : (state == .ahead ? .cyan : (state == .withPack ? .green : .secondary))
        return HStack(spacing: 8) {
            Image(systemName: state == .behind ? "arrow.down.right" : (state == .ahead ? "arrow.up.right" : "person.3.fill"))
            Text(state.label).font(.subheadline.weight(.semibold))
            Spacer()
            if let avg = snap?.pack.avgSpm, engine.mode == .pack {
                Text("pack \(Fmt.int(avg)) spm").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(color)
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var myStats: some View {
        let m = engine.metrics
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatTile(title: "Steps", value: Fmt.int(m.steps?.v), source: m.steps?.src)
                StatTile(title: "Steps/min", value: Fmt.int(m.spm?.v), source: m.spm?.src)
            }
            HStack(spacing: 10) {
                StatTile(title: "Heart rate", value: m.hr.map { Fmt.int($0.v) } ?? "—", source: m.hr?.src)
                StatTile(title: "Effort", value: m.effort.map { "\(Fmt.int($0.v))%" } ?? "—", source: m.effort?.src)
            }
        }
    }

    private var levelControl: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MACHINE LEVEL").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text("Set it to what the console says").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Button { engine.setLevel(engine.level - 1) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                .buttonStyle(.bordered)
            Text("\(engine.level)")
                .font(.system(.title, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .frame(width: 44)
                .contentTransition(.numericText())
            Button { engine.setLevel(engine.level + 1) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .card()
    }

    private var packRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THE PACK").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
            if others.isEmpty {
                Text("You're the first one here. Anyone who joins now climbs with you.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(others) { c in
                PackRow(climber: c, packAvg: snap?.pack.avgSpm)
            }
        }
        .card()
    }

    private var leaderboard: some View {
        let all = (snap?.climbers ?? []).sorted { ($0.metrics.steps?.v ?? 0) > ($1.metrics.steps?.v ?? 0) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("LEADERBOARD").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
            ForEach(Array(all.enumerated()), id: \.element.id) { i, c in
                let you = c.id == engine.identity.installId
                HStack {
                    Text("\(i + 1)").font(.system(.headline, design: .rounded, weight: .black)).frame(width: 28)
                        .foregroundStyle(i == 0 ? .yellow : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(you ? "You" : c.name).font(.subheadline.weight(you ? .bold : .semibold))
                        Text(c.where_).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(Fmt.int(c.metrics.steps?.v)).font(.headline.monospacedDigit())
                            if let s = c.metrics.steps?.src { SourceBadge(source: s) }
                        }
                        Text(c.finished ? "finished \(Fmt.clock(c.elapsed))" : "\(Fmt.int(c.metrics.spm?.v)) spm · L\(Fmt.int(c.metrics.level?.v))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .opacity(c.finished ? 0.6 : 1)
            }
        }
        .card()
    }

    private var cheers: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(client.cheers.suffix(3)) { c in
                Text("\(c.from): \(c.text)").font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(["Keep going!", "Who's still here?", "Legs are cooked"], id: \.self) { t in
                    Button(t) { client.cheer(t) }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomBar: some View {
        Button(role: .destructive) { confirmFinish = true } label: {
            Text("FINISH")
                .font(.system(.headline, design: .rounded, weight: .black))
                .tracking(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .padding(16)
        .background(.ultraThinMaterial)
    }
}

struct PackRow: View {
    var climber: Climber
    var packAvg: Double?

    private var delta: Double? {
        guard let packAvg, packAvg > 0, let s = climber.metrics.spm?.v else { return nil }
        return s / packAvg
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(climber.name).font(.subheadline.weight(.semibold))
                Text(climber.where_).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if climber.finished {
                Text("finished \(Fmt.clock(climber.elapsed))").font(.caption).foregroundStyle(.green)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("\(Fmt.int(climber.metrics.spm?.v)) spm").font(.subheadline.monospacedDigit())
                        if let s = climber.metrics.spm?.src { SourceBadge(source: s) }
                    }
                    Text("\(Fmt.clock(climber.elapsed)) · L\(Fmt.int(climber.metrics.level?.v))\(climber.metrics.effort.map { " · \(Fmt.int($0.v))%" } ?? "")")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Image(systemName: (delta ?? 1) < 0.85 ? "arrow.down" : ((delta ?? 1) > 1.15 ? "arrow.up" : "equal"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle((delta ?? 1) < 0.85 ? .orange : ((delta ?? 1) > 1.15 ? .cyan : .green))
                    .frame(width: 18)
            }
        }
        .padding(.vertical, 2)
    }
}
