import Foundation
import Observation

struct ProviderInfo: Identifiable {
    let id: String
    let displayName: String
    var model: String
    var endpoint: String
    var active: Bool
    var available: Bool
    var configured: Bool
}

@Observable
@MainActor
final class SettingsViewModel {
    var mcpServers: [MCPServerInfo] = []
    var isLoadingServers = false

    // Provider state
    var providers: [ProviderInfo] = []
    var activeProvider: String = "claude"
    var selectedProvider: String = "claude"  // Tracks picker selection (may differ from active before user confirms)
    var activeModel: String = ""
    var isLoadingProviders = false
    var providerError: String?
    var isSwitchingProvider = false

    // Ollama config fields (editable)
    var ollamaEndpoint: String = "http://localhost:11434/v1/chat/completions"
    var ollamaModel: String = "llama3"
    var isTestingOllama = false
    var ollamaTestResult: OllamaTestResult?

    // OpenAI config fields (editable)
    var openaiModel: String = "gpt-4o"

    enum OllamaTestResult {
        case success
        case failed(String)
    }

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

        case WSMessageType.providersStatus:
            handleProvidersStatus(msg)

        case WSMessageType.providerUpdated:
            handleProviderUpdated(msg)

        default:
            break
        }
    }

    // MARK: - Provider Actions

    func requestProvidersList() {
        isLoadingProviders = true
        webSocket.send(WSMessage(type: WSMessageType.getProviders))
    }

    func setProvider(_ name: String, endpoint: String? = nil, model: String? = nil) {
        isSwitchingProvider = true
        providerError = nil

        var metadata: [String: MetadataValue] = [
            "provider": .string(name)
        ]
        if let endpoint = endpoint {
            metadata["endpoint"] = .string(endpoint)
        }
        if let model = model {
            metadata["model"] = .string(model)
        }

        webSocket.send(WSMessage(
            type: WSMessageType.setProvider,
            metadata: metadata
        ))
    }

    func testOllamaConnection() {
        isTestingOllama = true
        ollamaTestResult = nil
        // Send a setProvider to test — the daemon will check reachability
        setProvider("ollama", endpoint: ollamaEndpoint, model: ollamaModel)
    }

    // MARK: - MCP Actions

    func requestMCPServersList() {
        isLoadingServers = true
        webSocket.send(WSMessage(type: WSMessageType.mcpServersList))
    }

    func toggleMCPServer(name: String, enabled: Bool) {
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

    private func handleProvidersStatus(_ msg: WSMessage) {
        isLoadingProviders = false
        guard let meta = msg.metadata else { return }

        activeProvider = meta["active"]?.stringValue ?? "claude"
        selectedProvider = activeProvider
        activeModel = meta["activeModel"]?.stringValue ?? ""

        guard case .array(let items) = meta["providers"] else { return }

        var loaded: [ProviderInfo] = []
        for item in items {
            guard case .object(let dict) = item else { continue }
            guard let name = dict["name"]?.stringValue else { continue }

            let info = ProviderInfo(
                id: name,
                displayName: dict["displayName"]?.stringValue ?? name,
                model: dict["model"]?.stringValue ?? "",
                endpoint: dict["endpoint"]?.stringValue ?? "",
                active: dict["active"]?.boolValue ?? false,
                available: dict["available"]?.boolValue ?? false,
                configured: dict["configured"]?.boolValue ?? true
            )
            loaded.append(info)

            // Populate editable fields from current provider configs
            if name == "ollama" {
                if !info.endpoint.isEmpty {
                    ollamaEndpoint = info.endpoint
                }
                if !info.model.isEmpty {
                    ollamaModel = info.model
                }
            } else if name == "openai" {
                if !info.model.isEmpty {
                    openaiModel = info.model
                }
            }
        }

        providers = loaded
    }

    private func handleProviderUpdated(_ msg: WSMessage) {
        isSwitchingProvider = false
        isTestingOllama = false
        guard let meta = msg.metadata else { return }

        let success = meta["success"]?.boolValue ?? false
        let provider = meta["provider"]?.stringValue ?? ""

        if success {
            activeProvider = provider
            selectedProvider = provider
            activeModel = meta["model"]?.stringValue ?? activeModel
            providerError = nil
            ollamaTestResult = .success

            // Update active state in providers list
            for i in providers.indices {
                providers[i].active = providers[i].id == provider
            }

            HapticManager.connectionEstablished()
        } else {
            let error = meta["error"]?.stringValue ?? "Unknown error"
            providerError = error
            selectedProvider = activeProvider  // Revert picker to actual active provider
            ollamaTestResult = .failed(error)
            HapticManager.toolError()
        }
    }

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
