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
    @State private var showAddServerSheet = false
    @State private var showDeleteServerAlert = false
    @State private var serverToDelete: String?

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
                cliToolsSection
                mcpServersSection
                if settingsVM.activeProvider == "ollama" {
                    ollamaToolsSection
                    pinnedToolsSection
                }
                ambientListeningSection
                aboutSection
                dataSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(.appBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.textSecondary)
                            .symbolRenderingMode(.hierarchical)
                    }
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
                            .foregroundStyle(.textSecondary)
                    }
                    .listRowBackground(Color.surface)
                } else {
                    HStack {
                        if bonjourBrowser.isSearching {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.textSecondary)
                            Text("Searching for daemons...")
                                .foregroundStyle(.textSecondary)
                                .padding(.leading, SolaceTheme.sm)
                        } else {
                            Text("No daemons found")
                                .foregroundStyle(.textSecondary)
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
                                    .foregroundStyle(.textSecondary)
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
                .foregroundStyle(.textSecondary.opacity(0.6))
                .listRowBackground(Color.surface)
        } header: {
            Text("DISCOVERED DAEMONS")
                .font(.sectionHeader)
                .foregroundStyle(.dusk)
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
                .padding(.vertical, SolaceTheme.xs)
            }
            .listRowBackground(Color.surface)
            .listRowSeparator(.hidden)
        } header: {
            Text("CONNECTION")
                .font(.sectionHeader)
                .foregroundStyle(.dusk)
                .tracking(1.2)
        }
    }

    @ViewBuilder
    private var testConnectionLabel: some View {
        switch testState {
        case .idle:
            Text("Test Connection")
                .foregroundStyle(.coral)

        case .testing:
            HStack(spacing: SolaceTheme.sm) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.textSecondary)
                Text("Testing...")
                    .foregroundStyle(.textSecondary)
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
                    .foregroundStyle(.textSecondary)
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
                        .tint(.textSecondary)
                    Text("Loading providers...")
                        .foregroundStyle(.textSecondary)
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
                            .foregroundStyle(.textSecondary)
                    }
                }
                .listRowBackground(Color.surface)

                // Provider picker
                VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                    Text("Provider")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.textSecondary)

                    HStack(spacing: SolaceTheme.sm) {
                        ForEach(["claude", "openai", "ollama"], id: \.self) { provider in
                            Button {
                                settings.selectedProvider = provider
                                if provider == "claude" {
                                    settingsVM.setProvider("claude")
                                }
                                if provider == "ollama" && settingsVM.ollamaModels.isEmpty {
                                    settingsVM.requestOllamaModels()
                                }
                            } label: {
                                Text(provider.capitalized)
                                    .font(.system(size: 13, weight: settings.selectedProvider == provider ? .semibold : .medium))
                                    .foregroundStyle(settings.selectedProvider == provider ? .white : .textPrimary)
                                    .padding(.horizontal, SolaceTheme.md)
                                    .padding(.vertical, SolaceTheme.sm)
                                    .frame(maxWidth: .infinity)
                                    .background(settings.selectedProvider == provider ? Color.coral : Color.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
                            }
                            .buttonStyle(.plain)
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
                        .foregroundStyle(.textSecondary.opacity(0.7))
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
                                    .tint(.textSecondary)
                                Text("Connecting...")
                                    .foregroundStyle(.textSecondary)
                            } else {
                                Text(settingsVM.activeProvider == "openai" ? "Update OpenAI" : "Connect to OpenAI")
                                    .foregroundStyle(.coral)
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
                                .tint(.textSecondary)
                        } else if settingsVM.ollamaModels.isEmpty {
                            TextField("e.g. qwen3.5",
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
                                        .foregroundStyle(settingsVM.ollamaModel.isEmpty ? .textSecondary : .textPrimary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.textSecondary)
                                }
                            }
                        }
                        Button {
                            settingsVM.requestOllamaModels()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                                .foregroundStyle(.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Color.surface)
                    .onChange(of: settingsVM.ollamaModels.map(\.id)) { _, modelIds in
                        guard !modelIds.isEmpty else { return }
                        let current = settingsVM.ollamaModel
                        let models = settingsVM.ollamaModels
                        let found = models.contains { $0.displayName == current || $0.name == current }
                        if current.isEmpty || !found {
                            if let first = models.first {
                                settingsVM.ollamaModel = first.displayName
                            }
                        }
                    }

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
                                    .tint(.textSecondary)
                                Text("Connecting...")
                                    .foregroundStyle(.textSecondary)
                            } else {
                                Text(settingsVM.activeProvider == "ollama" ? "Update Ollama" : "Connect to Ollama")
                                    .foregroundStyle(.coral)
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
                .foregroundStyle(.dusk)
                .tracking(1.2)
        }
        .onAppear {
            settingsVM.requestProvidersList()
        }
    }

    private var cliToolsSection: some View {
        Section {
            if settingsVM.isLoadingServers {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.textSecondary)
                    Text("Loading...")
                        .foregroundStyle(.textSecondary)
                        .padding(.leading, SolaceTheme.sm)
                    Spacer()
                }
                .listRowBackground(Color.surface)
            } else {
                let cliServers = settingsVM.mcpServers.filter { ServerBrandConfig.brand(for: $0.name).isCLI }
                if cliServers.isEmpty {
                    Text("No CLI tools configured")
                        .foregroundStyle(.textSecondary)
                        .listRowBackground(Color.surface)
                } else {
                    ForEach(cliServers) { server in
                        let brand = ServerBrandConfig.brand(for: server.name)
                        HStack(spacing: SolaceTheme.md) {
                            Image(systemName: brand.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(brand.color)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(brand.displayName)
                                    .foregroundStyle(.textPrimary)
                                Text("CLI \u{00B7} \(server.toolCount) tool\(server.toolCount == 1 ? "" : "s")")
                                    .font(.toolDetail)
                                    .foregroundStyle(.textSecondary)
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                serverToDelete = server.name
                                showDeleteServerAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        } header: {
            Text("CLI TOOLS")
                .font(.sectionHeader)
                .foregroundStyle(.dusk)
                .tracking(1.2)
        }
        .onAppear {
            settingsVM.requestMCPServersList()
        }
    }

    private var mcpServersSection: some View {
        Section {
            if settingsVM.isLoadingServers {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.textSecondary)
                    Text("Loading servers...")
                        .foregroundStyle(.textSecondary)
                        .padding(.leading, SolaceTheme.sm)
                    Spacer()
                }
                .listRowBackground(Color.surface)
            } else {
                let mcpOnlyServers = settingsVM.mcpServers.filter { !ServerBrandConfig.brand(for: $0.name).isCLI }
                if mcpOnlyServers.isEmpty {
                    Text("No MCP servers configured")
                        .foregroundStyle(.textSecondary)
                        .listRowBackground(Color.surface)
                } else {
                    ForEach(mcpOnlyServers) { server in
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
                                    .foregroundStyle(.textSecondary)
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                serverToDelete = server.name
                                showDeleteServerAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Button {
                showAddServerSheet = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.sageGreen)
                    Text("Add Server")
                        .foregroundStyle(.sageGreen)
                }
            }
            .listRowBackground(Color.surface)
        } header: {
            Text("MCP SERVERS")
                .font(.sectionHeader)
                .foregroundStyle(.dusk)
                .tracking(1.2)
        }
        .sheet(isPresented: $showAddServerSheet) {
            AddMCPServerSheet(settingsVM: settingsVM, isPresented: $showAddServerSheet)
        }
        .alert("Delete Server", isPresented: $showDeleteServerAlert) {
            Button("Cancel", role: .cancel) {
                serverToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let name = serverToDelete {
                    settingsVM.deleteMCPServer(name: name)
                    serverToDelete = nil
                }
            }
        } message: {
            if let name = serverToDelete {
                Text("Are you sure you want to remove \"\(name)\"? The server will be stopped and removed from your configuration.")
            }
        }
    }

    private var ollamaToolsSection: some View {
        Section {
            if settingsVM.mcpServers.isEmpty {
                Text("No MCP servers available")
                    .foregroundStyle(.textSecondary)
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
                                .foregroundStyle(.textSecondary)
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
                .foregroundStyle(.dusk)
                .tracking(1.2)
        } footer: {
            let ollamaToolCount = settingsVM.mcpServers
                .filter { $0.enabled && $0.ollamaEnabled }
                .reduce(0) { $0 + $1.toolCount }
            Text("\(ollamaToolCount) tool\(ollamaToolCount == 1 ? "" : "s") sent to Ollama. Disable servers with tools your local model doesn't need.")
                .foregroundStyle(.textSecondary.opacity(0.6))
        }
    }

    private var pinnedToolsSection: some View {
        Section {
            if settingsVM.isLoadingOllamaTools {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.textSecondary)
                    Text("Loading tools...")
                        .foregroundStyle(.textSecondary)
                        .padding(.leading, SolaceTheme.sm)
                    Spacer()
                }
                .listRowBackground(Color.surface)
            } else if settingsVM.ollamaTools.isEmpty {
                Text("No tools available")
                    .foregroundStyle(.textSecondary)
                    .listRowBackground(Color.surface)
            } else {
                ForEach(settingsVM.ollamaTools) { tool in
                    let atMax = settingsVM.pinnedToolsCount >= settingsVM.maxPinnedTools && !tool.pinned
                    HStack(spacing: SolaceTheme.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name)
                                .foregroundStyle(.textPrimary)
                                .font(.system(size: 14, weight: .medium))
                            Text(tool.serverName)
                                .font(.toolDetail)
                                .foregroundStyle(.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { tool.pinned },
                            set: { newValue in
                                settingsVM.togglePinnedTool(name: tool.name, pinned: newValue)
                            }
                        ))
                        .tint(.sageGreen)
                        .labelsHidden()
                        .disabled(atMax)
                    }
                    .opacity(atMax ? 0.5 : 1.0)
                    .listRowBackground(Color.surface)
                }

                if settingsVM.pinnedToolsCount > 0 {
                    Button {
                        settingsVM.clearAllPinnedTools()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Clear All Pins")
                                .foregroundStyle(.softRed)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.surface)
                }
            }
        } header: {
            HStack {
                Text("PINNED TOOLS")
                    .font(.sectionHeader)
                    .foregroundStyle(.textSecondary)
                    .tracking(1.2)
                Spacer()
                Text("\(settingsVM.pinnedToolsCount)/\(settingsVM.maxPinnedTools)")
                    .font(.toolDetail)
                    .foregroundStyle(.textSecondary.opacity(0.7))
            }
        } footer: {
            Text("Pin specific tools for small models. Pinned tools override automatic relevance-based selection.")
                .foregroundStyle(.textSecondary.opacity(0.6))
        }
        .onAppear {
            settingsVM.requestOllamaToolsList()
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
                .foregroundStyle(.dusk)
                .tracking(1.2)
        } footer: {
            Text("Continuously captures speech and sends it to Solace for analysis.")
                .foregroundStyle(.textSecondary.opacity(0.6))
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.textSecondary)
            }
            .listRowBackground(Color.surface)

            if let daemonVersion = webSocket.daemonVersion {
                HStack {
                    Text("Daemon")
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Text(daemonVersion)
                        .foregroundStyle(.textSecondary)
                }
                .listRowBackground(Color.surface)
            }

            HStack {
                Text("Tools Available")
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("\(webSocket.toolCount)")
                    .foregroundStyle(.textSecondary)
            }
            .listRowBackground(Color.surface)
        } header: {
            Text("ABOUT")
                .font(.sectionHeader)
                .foregroundStyle(.dusk)
                .tracking(1.2)
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                HStack(spacing: SolaceTheme.sm) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                    Text("Delete All Conversations")
                }
                .foregroundStyle(.error)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, SolaceTheme.xs)
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
                .foregroundStyle(.dusk)
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
