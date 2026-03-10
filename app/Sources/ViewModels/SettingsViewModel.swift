import Foundation
import Observation

struct OllamaModelInfo: Identifiable {
    let id: String  // model name
    let name: String
    let sizeGB: Double?

    var displayName: String {
        // Strip ":latest" suffix for cleaner display
        if name.hasSuffix(":latest") {
            return String(name.dropLast(7))
        }
        return name
    }

    var sizeLabel: String? {
        guard let gb = sizeGB else { return nil }
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else {
            let mb = gb * 1024
            return String(format: "%.0f MB", mb)
        }
    }
}

struct OllamaToolInfo: Identifiable {
    let id: String  // tool name
    let name: String
    let serverName: String
    let description: String
    var pinned: Bool
}

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
    var ollamaModel: String = "qwen3.5"
    var isTestingOllama = false
    var ollamaTestResult: OllamaTestResult?

    // Ollama installed models
    var ollamaModels: [OllamaModelInfo] = []
    var isLoadingOllamaModels = false

    // MCP server add/delete state
    var isAddingServer = false
    var addServerError: String?
    var isDeletingServer = false
    var deleteServerError: String?

    // Pinned tools for small Ollama models
    var ollamaTools: [OllamaToolInfo] = []
    var isLoadingOllamaTools = false
    var pinnedToolsCount: Int = 0
    let maxPinnedTools: Int = 5

    // OpenAI config fields (editable)
    var openaiModel: String = "gpt-4o"

    enum OllamaTestResult {
        case success
        case failed(String)
    }

    private let webSocket: WebSocketClient
    private var pinnedToolsDebounceTask: Task<Void, Never>?

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

        case WSMessageType.ollamaServerToggleResult:
            handleOllamaServerToggleResult(msg)

        case WSMessageType.mcpServerAddResult:
            handleMCPServerAddResult(msg)

        case WSMessageType.mcpServerDeleteResult:
            handleMCPServerDeleteResult(msg)

        case WSMessageType.providersStatus:
            handleProvidersStatus(msg)

        case WSMessageType.providerUpdated:
            handleProviderUpdated(msg)

        case WSMessageType.ollamaModelsList:
            handleOllamaModelsList(msg)

        case WSMessageType.ollamaToolsListResult:
            handleOllamaToolsListResult(msg)

        case WSMessageType.ollamaPinnedToolsResult:
            handleOllamaPinnedToolsResult(msg)

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

    func requestOllamaModels() {
        isLoadingOllamaModels = true
        webSocket.send(WSMessage(type: WSMessageType.getOllamaModels))
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

    func addMCPServer(name: String, type: String, command: String?, args: [String]?, url: String?, headers: [String: String]?) {
        isAddingServer = true
        addServerError = nil

        var metadata: [String: MetadataValue] = [
            "name": .string(name),
            "type": .string(type)
        ]
        if let command = command {
            metadata["command"] = .string(command)
        }
        if let args = args, !args.isEmpty {
            metadata["args"] = .array(args.map { .string($0) })
        }
        if let url = url {
            metadata["url"] = .string(url)
        }
        if let headers = headers, !headers.isEmpty {
            var obj: [String: MetadataValue] = [:]
            for (k, v) in headers { obj[k] = .string(v) }
            metadata["headers"] = .object(obj)
        }

        webSocket.send(WSMessage(
            type: WSMessageType.mcpServerAdd,
            metadata: metadata
        ))
    }

    func deleteMCPServer(name: String) {
        isDeletingServer = true
        deleteServerError = nil

        webSocket.send(WSMessage(
            type: WSMessageType.mcpServerDelete,
            metadata: ["name": .string(name)]
        ))
    }

    func toggleOllamaServer(name: String, enabled: Bool) {
        if let index = mcpServers.firstIndex(where: { $0.name == name }) {
            mcpServers[index].ollamaEnabled = enabled
        }

        webSocket.send(WSMessage(
            type: WSMessageType.ollamaServerToggle,
            metadata: [
                "serverName": .string(name),
                "enabled": .bool(enabled)
            ]
        ))
    }

    // MARK: - Pinned Tools Actions

    func requestOllamaToolsList() {
        isLoadingOllamaTools = true
        webSocket.send(WSMessage(type: WSMessageType.ollamaToolsList))
    }

    func togglePinnedTool(name: String, pinned: Bool) {
        // Update local state immediately for responsive UI
        if let index = ollamaTools.firstIndex(where: { $0.name == name }) {
            ollamaTools[index].pinned = pinned
        }
        pinnedToolsCount = ollamaTools.filter(\.pinned).count

        // Debounce WebSocket send — only the final state after 500ms of inactivity
        pinnedToolsDebounceTask?.cancel()
        pinnedToolsDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            let currentPinned = ollamaTools.filter(\.pinned).map { $0.name }
            webSocket.send(WSMessage(
                type: WSMessageType.ollamaPinnedToolsSet,
                metadata: [
                    "tools": .array(currentPinned.map { .string($0) })
                ]
            ))
        }
    }

    func clearAllPinnedTools() {
        for i in ollamaTools.indices {
            ollamaTools[i].pinned = false
        }
        pinnedToolsCount = 0

        webSocket.send(WSMessage(
            type: WSMessageType.ollamaPinnedToolsSet,
            metadata: [
                "tools": .array([])
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

    private func handleOllamaModelsList(_ msg: WSMessage) {
        isLoadingOllamaModels = false
        guard case .array(let items) = msg.metadata?["models"] else { return }

        var loaded: [OllamaModelInfo] = []
        for item in items {
            guard case .object(let dict) = item else { continue }
            guard let name = dict["name"]?.stringValue else { continue }

            loaded.append(OllamaModelInfo(
                id: name,
                name: name,
                sizeGB: dict["sizeGB"]?.doubleValue
            ))
        }

        ollamaModels = loaded
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
                ollamaEnabled: dict["ollamaEnabled"]?.boolValue ?? true,
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
                    ollamaEnabled: mcpServers[index].ollamaEnabled,
                    toolCount: toolCount
                )
            }
        }

        HapticManager.toolCompleted()
    }

    private func handleOllamaServerToggleResult(_ msg: WSMessage) {
        guard let meta = msg.metadata,
              let name = meta["serverName"]?.stringValue else { return }

        if let index = mcpServers.firstIndex(where: { $0.name == name }) {
            if let enabled = meta["enabled"]?.boolValue {
                mcpServers[index].ollamaEnabled = enabled
            }
        }

        HapticManager.toolCompleted()
    }

    private func handleMCPServerAddResult(_ msg: WSMessage) {
        isAddingServer = false
        guard let meta = msg.metadata else { return }

        let success = meta["success"]?.boolValue ?? false
        if success {
            addServerError = nil
            // Refresh the server list
            requestMCPServersList()
            HapticManager.toolCompleted()
        } else {
            addServerError = meta["error"]?.stringValue ?? "Failed to add server"
            HapticManager.toolError()
        }
    }

    private func handleMCPServerDeleteResult(_ msg: WSMessage) {
        isDeletingServer = false
        guard let meta = msg.metadata else { return }

        let success = meta["success"]?.boolValue ?? false
        if success {
            if let name = meta["name"]?.stringValue {
                mcpServers.removeAll { $0.name == name }
            }
            deleteServerError = nil
            HapticManager.toolCompleted()
        } else {
            deleteServerError = meta["error"]?.stringValue ?? "Failed to delete server"
            HapticManager.toolError()
        }
    }

    private func handleOllamaToolsListResult(_ msg: WSMessage) {
        isLoadingOllamaTools = false
        guard case .array(let items) = msg.metadata?["tools"] else { return }

        var loaded: [OllamaToolInfo] = []
        for item in items {
            guard case .object(let dict) = item else { continue }
            guard let name = dict["name"]?.stringValue else { continue }

            loaded.append(OllamaToolInfo(
                id: name,
                name: name,
                serverName: dict["serverName"]?.stringValue ?? "",
                description: dict["description"]?.stringValue ?? "",
                pinned: dict["pinned"]?.boolValue ?? false
            ))
        }

        ollamaTools = loaded
        pinnedToolsCount = msg.metadata?["pinnedCount"]?.intValue ?? loaded.filter(\.pinned).count
    }

    private func handleOllamaPinnedToolsResult(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }
        pinnedToolsCount = meta["pinnedCount"]?.intValue ?? 0
        HapticManager.toolCompleted()
    }
}
