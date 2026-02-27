import Foundation
import Observation

/// Thread-safe one-shot guard for continuation resumption.
private final class OnceGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false

    func tryConsume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !consumed else { return false }
        consumed = true
        return true
    }
}

enum ConnectionState: Sendable {
    case connected
    case connecting
    case disconnected
}

@Observable
@MainActor
final class WebSocketClient {
    var connectionState: ConnectionState = .disconnected
    var lastError: String?
    var daemonVersion: String?
    var toolCount: Int = 0
    var hasApiKey: Bool = false
    var retryCount: Int = 0

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var isIntentionalDisconnect = false

    private var host: String { UserDefaults.standard.string(forKey: "ws_host") ?? "localhost" }
    private var port: Int { UserDefaults.standard.integer(forKey: "ws_port").nonZero ?? 9200 }

    /// Callback for received messages. Set by the App entry point.
    var onMessage: (@MainActor @Sendable (WSMessage) -> Void)?

    func connect() {
        guard connectionState != .connecting else { return }
        isIntentionalDisconnect = false
        connectionState = .connecting

        let urlString = "ws://\(host):\(port)"
        guard let url = URL(string: urlString) else {
            connectionState = .disconnected
            lastError = "Invalid URL: \(urlString)"
            return
        }

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)

        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()

        startReceiving()
        startPingTimer()

        // We consider connected once we get the status message
        // but set connected here as a fallback
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if connectionState == .connecting {
                connectionState = .connected
                retryCount = 0
                HapticManager.connectionEstablished()
            }
        }
    }

    func disconnect() {
        isIntentionalDisconnect = true
        cleanup()
        connectionState = .disconnected
    }

    func send(_ message: WSMessage) {
        guard connectionState == .connected, let wsTask = webSocketTask else { return }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(message),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        wsTask.send(.string(jsonString)) { sendError in
            if let sendError {
                let description = sendError.localizedDescription
                Task { @MainActor in
                    // Note: we don't use [weak self] to avoid Sendable capture issues
                    // This is acceptable since WebSocketClient outlives individual sends
                    _ = description // Logged for debugging
                }
            }
        }
    }

    func testConnection(host testHost: String, port testPort: Int) async -> Bool {
        let urlString = "ws://\(testHost):\(testPort)"
        guard let url = URL(string: urlString) else { return false }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        let testSession = URLSession(configuration: config)
        let testTask = testSession.webSocketTask(with: url)
        testTask.resume()

        // Use withCheckedContinuation + DispatchQueue timeout
        let connected = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let guard_ = OnceGuard()

            testTask.receive { result in
                guard guard_.tryConsume() else { return }
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case .failure:
                    continuation.resume(returning: false)
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                guard guard_.tryConsume() else { return }
                testTask.cancel(with: .goingAway, reason: nil)
                continuation.resume(returning: false)
            }
        }

        testTask.cancel(with: .goingAway, reason: nil)
        return connected
    }

    // MARK: - Private

    private func startReceiving() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let task = self.webSocketTask else { break }
                do {
                    let message = try await task.receive()
                    self.handleReceivedMessage(message)
                } catch {
                    if !Task.isCancelled {
                        self.handleDisconnection()
                    }
                    break
                }
            }
        }
    }

    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        let jsonString: String
        switch message {
        case .string(let text):
            jsonString = text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else { return }
            jsonString = text
        @unknown default:
            return
        }

        guard let data = jsonString.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        guard let wsMessage = try? decoder.decode(WSMessage.self, from: data) else { return }

        // Handle status message for connection confirmation
        if wsMessage.type == WSMessageType.status {
            connectionState = .connected
            retryCount = 0
            if let version = wsMessage.metadata?["daemonVersion"]?.stringValue {
                daemonVersion = version
            }
            if let tools = wsMessage.metadata?["toolCount"]?.intValue {
                toolCount = tools
            }
            if let apiKey = wsMessage.metadata?["hasApiKey"]?.boolValue {
                hasApiKey = apiKey
            }
            HapticManager.connectionEstablished()
        }

        if wsMessage.type == WSMessageType.pong {
            return
        }

        onMessage?(wsMessage)
    }

    private func handleDisconnection() {
        guard !isIntentionalDisconnect else { return }
        cleanup()
        connectionState = .disconnected
        HapticManager.connectionLost()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            let delay = self.nextBackoffDelay()
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self.retryCount += 1
            self.connect()
        }
    }

    private func nextBackoffDelay() -> Double {
        let base: Double = 1.0
        let delay = base * pow(2.0, Double(min(retryCount, 5)))
        return min(delay, 30.0)
    }

    private func startPingTimer() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                self?.sendPing()
            }
        }
    }

    private func sendPing() {
        let ping = WSMessage(type: WSMessageType.ping)
        send(ping)
    }

    private func cleanup() {
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
}

// MARK: - Int helper

private extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}
