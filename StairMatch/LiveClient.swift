import Foundation
import Observation

struct Cheer: Identifiable, Equatable {
    let id = UUID()
    let from: String
    let text: String
    let at = Date()
}

/// Talks to the relay: the live board (REST) and one room (WebSocket).
@MainActor
@Observable
final class LiveClient {
    var board: LiveBoard = .empty
    var boardError: String?
    var snapshot: RoomSnapshot?
    var youId: String?
    var connected = false
    var cheers: [Cheer] = []

    private let session = URLSession(configuration: .default)
    private var socket: URLSessionWebSocketTask?
    private var pollTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: Live board

    func startPolling(every seconds: Double = 5) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchBoard()
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func fetchBoard() async {
        do {
            let (data, _) = try await session.data(from: RelayConfig.baseURL.appending(path: "v1/live"))
            board = try decoder.decode(LiveBoard.self, from: data)
            boardError = nil
        } catch {
            boardError = error.localizedDescription
        }
    }

    // MARK: Room

    func join(mode: RoomMode) async throws -> String {
        var req = URLRequest(url: RelayConfig.baseURL.appending(path: "v1/join"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(["mode": mode.rawValue])
        let (data, _) = try await session.data(for: req)
        struct JoinReply: Decodable { var roomId: String }
        return try decoder.decode(JoinReply.self, from: data).roomId
    }

    func connect(roomId: String, id: String, name: String, city: String?) {
        disconnect()
        var comps = URLComponents(url: RelayConfig.baseURL.appending(path: "v1/rooms/\(roomId)/ws"), resolvingAgainstBaseURL: false)!
        comps.scheme = comps.scheme == "http" ? "ws" : "wss"
        comps.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "city", value: city),
        ]
        let task = session.webSocketTask(with: comps.url!)
        socket = task
        task.resume()
        connected = true
        receive()
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                self?.socket?.send(.string("ping")) { _ in }
            }
        }
    }

    func send(_ message: some Encodable) {
        guard let socket, let data = try? encoder.encode(message), let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { [weak self] error in
            if error != nil { Task { @MainActor in self?.connected = false } }
        }
    }

    func sendTelemetry(elapsed: Double, metrics: Metrics) {
        send(TelemetryMessage(elapsed: elapsed, metrics: metrics))
    }

    func finish() { send(["type": "finish"]) }

    func cheer(_ text: String) { send(["type": "cheer", "text": text]) }

    func disconnect() {
        pingTask?.cancel()
        pingTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connected = false
        snapshot = nil
        youId = nil
        cheers = []
    }

    private func receive() {
        guard let socket else { return }
        socket.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure:
                    self.connected = false
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receive()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard text != "pong", let data = text.data(using: .utf8),
              let env = try? decoder.decode(ServerEnvelope.self, from: data) else { return }
        switch env.type {
        case "hello", "snapshot":
            if let snap = try? decoder.decode(RoomSnapshot.self, from: data) { snapshot = snap }
            if let you = env.you { youId = you }
        case "cheer":
            cheers.append(Cheer(from: env.from ?? "Someone", text: env.text ?? ""))
            if cheers.count > 5 { cheers.removeFirst(cheers.count - 5) }
        default:
            break
        }
    }
}
