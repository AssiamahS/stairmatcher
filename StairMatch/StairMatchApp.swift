import SwiftUI

@main
struct StairMatchApp: App {
    @State private var engine = SessionEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .preferredColorScheme(.dark)
                .tint(Color.accentColor)
        }
    }
}

struct RootView: View {
    @Environment(SessionEngine.self) private var engine
    private let identity = Identity.shared

    var body: some View {
        Group {
            if identity.name.isEmpty {
                SetupView(firstRun: true)
            } else {
                switch engine.phase {
                case .idle: LobbyView()
                case .joining, .climbing: SessionView()
                case .finished: SummaryView()
                }
            }
        }
        .animation(.snappy, value: engine.phase)
    }
}
