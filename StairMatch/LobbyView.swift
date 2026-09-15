import SwiftUI

/// "Who else is climbing right now?" — the whole product in one screen.
struct LobbyView: View {
    @Environment(SessionEngine.self) private var engine
    @State private var showSetup = false
    @State private var mode: RoomMode = .pack

    private var client: LiveClient { engine.client }
    private var board: LiveBoard { client.board }

    private var columns: [GridItem] { [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    modePicker
                    if board.climbers.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(board.climbers.filter { $0.mode == mode }) { c in
                                ClimberCard(climber: c, isYou: c.id == engine.identity.installId)
                            }
                        }
                        let otherMode = board.climbers.filter { $0.mode != mode }.count
                        if otherMode > 0 {
                            Text("\(otherMode) more in \(mode == .pack ? "Race" : "Pack") rooms")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let err = engine.joinError ?? client.boardError {
                        Text(err).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }
                }
                .padding(16)
                .padding(.bottom, 120)
            }
            .background(Color(red: 0.039, green: 0.043, blue: 0.055).ignoresSafeArea())
            .navigationTitle("StairMatch")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSetup = true } label: { Image(systemName: "person.crop.circle") }
                }
            }
            .safeAreaInset(edge: .bottom) { joinBar }
            .sheet(isPresented: $showSetup) { SetupView(firstRun: false) }
        }
        .task {
            engine.identity.requestCity()
            client.startPolling()
        }
        .onDisappear { client.stopPolling() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("LIVE STAIRMASTER NETWORK")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.green.opacity(0.4), lineWidth: 6).scaleEffect(1.4))
                Text("\(board.climbing) climbing right now")
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .contentTransition(.numericText())
            }
            let cities = Set(board.climbers.compactMap(\.city)).count
            Text(board.climbing == 0 ? "Nobody's on the stairs yet. Be the first — others join you live."
                 : "\(board.rooms.count) room\(board.rooms.count == 1 ? "" : "s") · \(cities) cit\(cities == 1 ? "y" : "ies")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .card()
    }

    private var modePicker: some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: $mode) {
                ForEach(RoomMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(mode.blurb).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.stairs")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("Never climb alone.")
                .font(.headline)
            Text("Get on the machine, tap Join, and anyone who starts after you lands in your room. Your Watch sends heart rate and cadence; you set the level.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .card()
    }

    private var joinBar: some View {
        VStack(spacing: 8) {
            Button {
                Task { await engine.start(mode: mode) }
            } label: {
                HStack {
                    if engine.phase == .joining { ProgressView().tint(.black) }
                    Text(engine.phase == .joining ? "Joining…" : "JOIN CLIMB")
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .tracking(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(engine.phase != .idle)
            HStack(spacing: 6) {
                Image(systemName: engine.watch.reachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                Text(engine.watch.reachable ? "Watch connected" : "Watch not reachable — cadence will be estimated from your level")
            }
            .font(.caption2)
            .foregroundStyle(engine.watch.reachable ? .green : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }
}
