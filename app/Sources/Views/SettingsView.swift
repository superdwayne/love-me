import SwiftUI

struct SettingsView: View {
    @Environment(WebSocketClient.self) private var webSocket
    @Environment(BonjourBrowser.self) private var bonjourBrowser
    @Environment(SettingsViewModel.self) private var settingsVM
    @Environment(AmbientListeningViewModel.self) private var ambientVM
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ws_host") private var host = "localhost"
    @AppStorage("ws_port") private var port = 9200
    @State private var testState: TestState = .idle
    @State private var showDeleteAlert = false

    enum TestState {
        case idle
        case testing
        case success
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            List {
                discoveredDaemonsSection
                connectionSection
                aiProviderSection
                mcpServersSection
                if settingsVM.activeProvider == "ollama" {
                    ollamaToolsSection
                }
                ambientListeningSection
                aboutSection
                dataSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(.appBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.textPrimary)
                }
            }
            .toolbarBackground(.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Sections

    private var discoveredDaemonsSection: some View {
        Section {
            if bonjourBrowser.discoveredDaemons.isEmpty {
                if bonjourBrowser.permissionDenied {
                    VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                        Text("Local Network access denied")
                            .foregroundStyle(.softRed)
                        Text("Enable in Settings > Privacy > Local Network")
                            .font(.toolDetail)
                            .foregroundStyle(.trust)
                    }
                    .listRowBackground(Color.surface)
                } else {
                    HStack {
                        if bonjourBrowser.isSearching {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.trust)
                            Text("Searching for daemons...")
                                .foregroundStyle(.trust)
                                .padding(.leading, SolaceTheme.sm)
                        } else {
                            Text("No daemons found")
                                .foregroundStyle(.trust)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.surface)
                }
            } else {
                ForEach(bonjourBrowser.discoveredDaemons) { daemon in
                    Button {
                        selectDaemon(daemon)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(daemon.name)
                                    .foregroundStyle(.textPrimary)
                                Text(daemon.displayAddress)
                                    .font(.toolDetail)
                                    .foregroundStyle(.trust)
                            }
                            Spacer()
                            if host == daemon.host && port == Int(daemon.port) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.sageGreen)
                            }
                        }
                    }
                    .listRowBackground(Color.surface)
                }
            }
            // Debug info
            Text(bonjourBrowser.debugStatus)
                .font(.toolDetail)
                .foregroundStyle(.trust.opacity(0.6))
                .listRowBackground(Color.surface)
        } header: {
            Text("DISCOVERED DAEMONS")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    private var connectionSection: some View {
        Section {
            HStack {
                Text("Host")
                    .foregroundStyle(.textPrimary)
                Spacer()
                TextField("localhost", text: $host)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .listRowBackground(Color.surface)

            HStack {
                Text("Port")
                    .foregroundStyle(.textPrimary)
                Spacer()
                TextField("9200", value: $port, format: .number)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.textPrimary)
                    .keyboardType(.numberPad)
            }
            .listRowBackground(Color.surface)

            Button {
                testConnection()
            } label: {
                HStack {
                    Spacer()
                    testConnectionLabel
                    Spacer()
                }
            }
            .listRowBackground(Color.surface)
        } header: {
            Text("CONNECTION")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    @ViewBuilder
    private var testConnectionLabel: some View {
        switch testState {
        case .idle:
            Text("Test Connection")
                .foregroundStyle(.heart)

        case .testing:
            HStack(spacing: SolaceTheme.sm) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.trust)
                Text("Testing...")
                    .foregroundStyle(.trust)
            }

        case .success:
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.sageGreen)
                Text("Connected")
                    .foregroundStyle(.sageGreen)
            }

        case .failed(let error):
            VStack(spacing: SolaceTheme.xs) {
                HStack(spacing: SolaceTheme.sm) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.softRed)
                    Text("Connection Failed")
                        .foregroundStyle(.softRed)
                }
                Text(error)
                    .font(.toolDetail)
                    .foregroundStyle(.trust)
            }
        }
    }

    @ViewBuilder
    private var aiProviderSection: some View {
        @Bindable var settings = settingsVM

        Section {
            if settingsVM.isLoadingProviders {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.trust)
                    Text("Loading providers...")
                        .foregroundStyle(.trust)
                        .padding(.leading, SolaceTheme.sm)
                    Spacer()
                }
                .listRowBackground(Color.surface)
            } else {
                // Active provider indicator
                HStack {
                    Text("Active")
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    HStack(spacing: SolaceTheme.xs) {
                        Circle()
                            .fill(Color.sageGreen)
                            .frame(width: 8, height: 8)
                        Text(activeProviderLabel)
                            .foregroundStyle(.trust)
                    }
                }
                .listRowBackground(Color.surface)

                // Provider picker
                HStack {
                    Text("Provider")
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Picker("", selection: $settings.selectedProvider) {
                        Text("Claude").tag("claude")
                        Text("OpenAI").tag("openai")
                        Text("Ollama").tag("ollama")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .onChange(of: settingsVM.selectedProvider) { _, newValue in
                        if newValue == "claude" {
                            settingsVM.setProvider("claude")
                        }
                        if newValue == "ollama" && settingsVM.ollamaModels.isEmpty {
                            settingsVM.requestOllamaModels()
                        }
                    }
                }
                .listRowBackground(Color.surface)

                // OpenAI configuration fields
                if settingsVM.selectedProvider == "openai" {
                    HStack {
                        Text("Model")
                            .foregroundStyle(.textPrimary)
                        Spacer()
                        TextField("gpt-4o",
                                  text: Binding(
                                    get: { settingsVM.openaiModel },
                                    set: { settingsVM.openaiModel = $0 }
                                  ))
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .listRowBackground(Color.surface)

                    Text("API key is configured on the daemon via OPENAI_API_KEY in ~/.solace/.env")
                        .font(.toolDetail)
                        .foregroundStyle(.trust.opacity(0.7))
                        .listRowBackground(Color.surface)

                    // Connect button
                    Button {
                        settingsVM.setProvider("openai",
                                               model: settingsVM.openaiModel)
                    } label: {
                        HStack {
                            Spacer()
                            if settingsVM.isSwitchingProvider {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.trust)
                                Text("Connecting...")
                                    .foregroundStyle(.trust)
                            } else {
                                Text(settingsVM.activeProvider == "openai" ? "Update OpenAI" : "Connect to OpenAI")
                                    .foregroundStyle(.heart)
                            }
                            Spacer()
                        }
                    }
                    .disabled(settingsVM.isSwitchingProvider)
                    .listRowBackground(Color.surface)

                    // Error message
                    if let error = settingsVM.providerError {
                        HStack(spacing: SolaceTheme.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.softRed)
                                .font(.system(size: 12))
                            Text(error)
                                .font(.toolDetail)
                                .foregroundStyle(.softRed)
                        }
                        .listRowBackground(Color.surface)
                    }
                }

                // Ollama configuration fields (shown when Ollama is selected or configured)
                if settingsVM.selectedProvider == "ollama" {
                    HStack {
                        Text("Endpoint")
                            .foregroundStyle(.textPrimary)
                        Spacer()
                        TextField("http://localhost:11434/v1/chat/completions",
                                  text: Binding(
                                    get: { settingsVM.ollamaEndpoint },
                                    set: { settingsVM.ollamaEndpoint = $0 }
                                  ))
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(size: 13))
                    }
                    .listRowBackground(Color.surface)
                    .onAppear {
                        if settingsVM.ollamaModels.isEmpty && !settingsVM.isLoadingOllamaModels {
                            settingsVM.requestOllamaModels()
                        }
                    }

                    // Model picker with installed models
                    HStack {
                        Text("Model")
                            .foregroundStyle(.textPrimary)
                        Spacer()
                        if settingsVM.isLoadingOllamaModels {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.trust)
                        } else if settingsVM.ollamaModels.isEmpty {
                            TextField("qwen3",
                                      text: Binding(
                                        get: { settingsVM.ollamaModel },
                                        set: { settingsVM.ollamaModel = $0 }
                                      ))
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.textPrimary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            Menu {
                                ForEach(settingsVM.ollamaModels) { model in
                                    Button {
                                        settingsVM.ollamaModel = model.displayName
                                    } label: {
                                        HStack {
                                            Text(model.displayName)
                                            if let size = model.sizeLabel {
                                                Text(size)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: SolaceTheme.xs) {
                                    Text(settingsVM.ollamaModel.isEmpty ? "Select model" : settingsVM.ollamaModel)
                                        .foregroundStyle(settingsVM.ollamaModel.isEmpty ? .trust : .textPrimary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.trust)
                                }
                            }
                        }
                        Button {
                            settingsVM.requestOllamaModels()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                                .foregroundStyle(.trust)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Color.surface)

                    // Connect / Test button
                    Button {
                        settingsVM.setProvider("ollama",
                                               endpoint: settingsVM.ollamaEndpoint,
                                               model: settingsVM.ollamaModel)
                    } label: {
                        HStack {
                            Spacer()
                            if settingsVM.isSwitchingProvider {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.trust)
                                Text("Connecting...")
                                    .foregroundStyle(.trust)
                            } else {
                                Text(settingsVM.activeProvider == "ollama" ? "Update Ollama" : "Connect to Ollama")
                                    .foregroundStyle(.heart)
                            }
                            Spacer()
                        }
                    }
                    .disabled(settingsVM.isSwitchingProvider)
                    .listRowBackground(Color.surface)

                    // Error message
                    if let error = settingsVM.providerError {
                        HStack(spacing: SolaceTheme.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.softRed)
                                .font(.system(size: 12))
                            Text(error)
                                .font(.toolDetail)
                                .foregroundStyle(.softRed)
                        }
                        .listRowBackground(Color.surface)
                    }
                }
            }
        } header: {
            Text("AI PROVIDER")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
        .onAppear {
            settingsVM.requestProvidersList()
        }
    }

    private var mcpServersSection: some View {
        Section {
            if settingsVM.isLoadingServers {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.trust)
                    Text("Loading servers...")
                        .foregroundStyle(.trust)
                        .padding(.leading, SolaceTheme.sm)
                    Spacer()
                }
                .listRowBackground(Color.surface)
            } else if settingsVM.mcpServers.isEmpty {
                Text("No MCP servers configured")
                    .foregroundStyle(.trust)
                    .listRowBackground(Color.surface)
            } else {
                ForEach(settingsVM.mcpServers) { server in
                    let brand = ServerBrandConfig.brand(for: server.name)
                    HStack(spacing: SolaceTheme.md) {
                        Image(systemName: brand.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(brand.color)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(brand.displayName)
                                .foregroundStyle(.textPrimary)
                            Text("\(server.type) \u{00B7} \(server.toolCount) tool\(server.toolCount == 1 ? "" : "s")")
                                .font(.toolDetail)
                                .foregroundStyle(.trust)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { server.enabled },
                            set: { newValue in
                                settingsVM.toggleMCPServer(name: server.name, enabled: newValue)
                            }
                        ))
                        .tint(.sageGreen)
                        .labelsHidden()
                    }
                    .listRowBackground(Color.surface)
                }
            }
        } header: {
            Text("MCP SERVERS")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
        .onAppear {
            settingsVM.requestMCPServersList()
        }
    }

    private var ollamaToolsSection: some View {
        Section {
            if settingsVM.mcpServers.isEmpty {
                Text("No MCP servers available")
                    .foregroundStyle(.trust)
                    .listRowBackground(Color.surface)
            } else {
                ForEach(settingsVM.mcpServers.filter { $0.enabled }) { server in
                    let brand = ServerBrandConfig.brand(for: server.name)
                    HStack(spacing: SolaceTheme.md) {
                        Image(systemName: brand.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(brand.color)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(brand.displayName)
                                .foregroundStyle(.textPrimary)
                            Text("\(server.toolCount) tool\(server.toolCount == 1 ? "" : "s")")
                                .font(.toolDetail)
                                .foregroundStyle(.trust)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { server.ollamaEnabled },
                            set: { newValue in
                                settingsVM.toggleOllamaServer(name: server.name, enabled: newValue)
                            }
                        ))
                        .tint(.sageGreen)
                        .labelsHidden()
                    }
                    .listRowBackground(Color.surface)
                }
            }
        } header: {
            Text("OLLAMA TOOLS")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        } footer: {
            let ollamaToolCount = settingsVM.mcpServers
                .filter { $0.enabled && $0.ollamaEnabled }
                .reduce(0) { $0 + $1.toolCount }
            Text("\(ollamaToolCount) tool\(ollamaToolCount == 1 ? "" : "s") sent to Ollama. Disable servers with tools your local model doesn't need.")
                .foregroundStyle(.trust.opacity(0.6))
        }
    }

    private var ambientListeningSection: some View {
        Section {
            HStack {
                Text("Ambient Listening")
                    .foregroundStyle(.textPrimary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { ambientVM.isListening },
                    set: { _ in ambientVM.toggleListening() }
                ))
                .tint(.sageGreen)
                .labelsHidden()
            }
            .listRowBackground(Color.surface)
        } header: {
            Text("AMBIENT LISTENING")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        } footer: {
            Text("Continuously captures speech and sends it to Solace for analysis.")
                .foregroundStyle(.trust.opacity(0.6))
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.trust)
            }
            .listRowBackground(Color.surface)

            if let daemonVersion = webSocket.daemonVersion {
                HStack {
                    Text("Daemon")
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Text(daemonVersion)
                        .foregroundStyle(.trust)
                }
                .listRowBackground(Color.surface)
            }

            HStack {
                Text("Tools Available")
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("\(webSocket.toolCount)")
                    .foregroundStyle(.trust)
            }
            .listRowBackground(Color.surface)
        } header: {
            Text("ABOUT")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                HStack {
                    Spacer()
                    Text("Delete All Conversations")
                        .foregroundStyle(.softRed)
                    Spacer()
                }
            }
            .listRowBackground(Color.surface)
            .alert("Delete All Conversations", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    // Will be implemented when backend supports bulk delete
                }
            } message: {
                Text("Are you sure you want to delete all conversations? This cannot be undone.")
            }
        } header: {
            Text("DATA")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    // MARK: - Computed Properties

    private var activeProviderLabel: String {
        switch settingsVM.activeProvider {
        case "ollama":
            return "Ollama: \(settingsVM.activeModel)"
        case "openai":
            return "OpenAI: \(settingsVM.activeModel)"
        default:
            return "Claude"
        }
    }

    // MARK: - Actions

    private func selectDaemon(_ daemon: DiscoveredDaemon) {
        host = daemon.host
        port = Int(daemon.port)
        webSocket.disconnect()
        webSocket.connect()
        testState = .idle
        HapticManager.connectionEstablished()
    }

    private func testConnection() {
        testState = .testing
        let testHost = host
        let testPort = port
        Task {
            let success = await webSocket.testConnection(host: testHost, port: testPort)
            if success {
                testState = .success
                HapticManager.connectionEstablished()
            } else {
                testState = .failed("Could not connect to \(testHost):\(testPort)")
                HapticManager.toolError()
            }
        }
    }
}
