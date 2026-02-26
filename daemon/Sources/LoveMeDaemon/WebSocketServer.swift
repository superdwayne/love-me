import Foundation
import Network

/// Represents a connected WebSocket client
actor WebSocketClient {
    nonisolated let id: String
    private let connection: NWConnection
    private let encoder = JSONEncoder()

    init(connection: NWConnection) {
        self.id = UUID().uuidString
        self.connection = connection
    }

    func send(_ message: WSMessage) async throws {
        let data = try encoder.encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw WebSocketError.encodingFailed
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "textMessage",
            metadata: [metadata]
        )

        let conn = connection
        try await withTimeout(seconds: 10) {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                conn.send(
                    content: text.data(using: .utf8),
                    contentContext: context,
                    isComplete: true,
                    completion: .contentProcessed { error in
                        if let error = error {
                            cont.resume(throwing: error)
                        } else {
                            cont.resume()
                        }
                    }
                )
            }
        }
    }

    func cancel() {
        connection.cancel()
    }

    nonisolated var connectionRef: NWConnection { connection }
}

enum WebSocketError: Error, Sendable {
    case encodingFailed
    case connectionFailed(String)
    case serverStartFailed(String)
}

/// WebSocket server using Network.framework
actor WebSocketServer {
    private var listener: NWListener?
    private var clients: [String: WebSocketClient] = [:]
    private let port: UInt16
    private var messageHandler: (@Sendable (WebSocketClient, WSMessage) async -> Void)?
    private var connectionHandler: (@Sendable (WebSocketClient) async -> Void)?

    init(port: UInt16) {
        self.port = port
    }

    func setMessageHandler(_ handler: @escaping @Sendable (WebSocketClient, WSMessage) async -> Void) {
        self.messageHandler = handler
    }

    func setConnectionHandler(_ handler: @escaping @Sendable (WebSocketClient) async -> Void) {
        self.connectionHandler = handler
    }

    func start() throws {
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw WebSocketError.serverStartFailed("Invalid port: \(port)")
        }

        let newListener = try NWListener(using: params, on: nwPort)

        newListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Logger.info("WebSocket server listening on port \(self.port)")
            case .failed(let error):
                Logger.error("WebSocket server failed: \(error)")
            case .cancelled:
                Logger.info("WebSocket server cancelled")
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            Task {
                await self.handleNewConnection(connection)
            }
        }

        newListener.start(queue: .main)
        self.listener = newListener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for client in clients.values {
            Task { await client.cancel() }
        }
        clients.removeAll()
    }

    func broadcast(_ message: WSMessage) async {
        var failedIds: [String] = []
        for (id, client) in clients {
            do {
                try await withTimeout(seconds: 5) {
                    try await client.send(message)
                }
            } catch {
                Logger.error("Broadcast failed for client \(id): \(error)")
                failedIds.append(id)
            }
        }
        // Remove clients that failed to receive
        for id in failedIds {
            clients.removeValue(forKey: id)
        }
    }

    var clientCount: Int {
        clients.count
    }

    // MARK: - Private

    private func handleNewConnection(_ connection: NWConnection) {
        let client = WebSocketClient(connection: connection)
        let clientId = client.id

        clients[clientId] = client
        Logger.info("Client connected: \(clientId)")

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                Logger.info("Client \(clientId) connection ready")
                Task {
                    await self.connectionHandler?(client)
                    await self.receiveLoop(client: client)
                }
            case .failed(let error):
                Logger.error("Client \(clientId) connection failed: \(error)")
                Task { await self.removeClient(clientId) }
            case .cancelled:
                Logger.info("Client \(clientId) disconnected")
                Task { await self.removeClient(clientId) }
            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    private func removeClient(_ id: String) {
        clients.removeValue(forKey: id)
        Logger.info("Client removed: \(id) (total: \(clients.count))")
    }

    private func receiveLoop(client: WebSocketClient) {
        let connection = client.connectionRef
        receiveMessage(on: connection, client: client)
    }

    private nonisolated func receiveMessage(on connection: NWConnection, client: WebSocketClient) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self = self else { return }

            if let error = error {
                Logger.error("Receive error: \(error)")
                Task { await self.removeClient(client.id) }
                return
            }

            if let data = content,
               let wsMetadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {

                switch wsMetadata.opcode {
                case .text:
                    if let text = String(data: data, encoding: .utf8) {
                        Task {
                            await self.handleTextMessage(text, from: client)
                        }
                    }
                case .close:
                    Task { await self.removeClient(client.id) }
                    return
                default:
                    break
                }
            }

            // Continue receiving
            self.receiveMessage(on: connection, client: client)
        }
    }

    private func handleTextMessage(_ text: String, from client: WebSocketClient) async {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let message = try JSONDecoder().decode(WSMessage.self, from: data)
            await messageHandler?(client, message)
        } catch {
            Logger.error("Failed to decode WebSocket message: \(error)")
            let errorMsg = WSMessage(
                type: WSMessageType.error,
                content: "Invalid message format",
                metadata: ["code": .string("INVALID_MESSAGE")]
            )
            try? await client.send(errorMsg)
        }
    }
}
