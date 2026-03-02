import Foundation
import Observation

@Observable
@MainActor
final class SettingsViewModel {
    var mcpServers: [MCPServerInfo] = []
    var isLoadingServers = false

    private let webSocket: WebSocketClient

    init(webSocket: WebSocketClient) {
        self.webSocket = webSocket
    }

    // MARK: - Message Handling

    func handleMessage(_ msg: WSMessage) {
        switch msg.type {
        case WSMessageType.mcpServersListResult:
            handleMCPServersListResult(msg)

        case WSMessageType.mcpServerToggleResult:
            handleMCPServerToggleResult(msg)

        default:
            break
        }
    }

    // MARK: - Actions

    func requestMCPServersList() {
        isLoadingServers = true
        webSocket.send(WSMessage(type: WSMessageType.mcpServersList))
    }

    func toggleMCPServer(name: String, enabled: Bool) {
        // Optimistic update
        if let index = mcpServers.firstIndex(where: { $0.name == name }) {
            mcpServers[index].enabled = enabled
        }

        webSocket.send(WSMessage(
            type: WSMessageType.mcpServerToggle,
            metadata: [
                "serverName": .string(name),
                "enabled": .bool(enabled)
            ]
        ))
    }

    // MARK: - Private Handlers

    private func handleMCPServersListResult(_ msg: WSMessage) {
        isLoadingServers = false
        guard case .array(let items) = msg.metadata?["servers"] else { return }

        var loaded: [MCPServerInfo] = []
        for item in items {
            guard case .object(let dict) = item else { continue }
            guard let name = dict["name"]?.stringValue else { continue }

            loaded.append(MCPServerInfo(
                name: name,
                type: dict["type"]?.stringValue ?? "stdio",
                enabled: dict["enabled"]?.boolValue ?? true,
                toolCount: dict["toolCount"]?.intValue ?? 0
            ))
        }

        mcpServers = loaded
    }

    private func handleMCPServerToggleResult(_ msg: WSMessage) {
        guard let meta = msg.metadata,
              let name = meta["serverName"]?.stringValue else { return }

        if let index = mcpServers.firstIndex(where: { $0.name == name }) {
            if let enabled = meta["enabled"]?.boolValue {
                mcpServers[index].enabled = enabled
            }
            if let toolCount = meta["toolCount"]?.intValue {
                // Tool count may change when toggling (e.g., 0 when disabled)
                mcpServers[index] = MCPServerInfo(
                    name: mcpServers[index].name,
                    type: mcpServers[index].type,
                    enabled: mcpServers[index].enabled,
                    toolCount: toolCount
                )
            }
        }

        HapticManager.toolCompleted()
    }
}
