import SwiftUI

struct SettingsView: View {
    @Environment(WebSocketClient.self) private var webSocket
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ws_host") private var host = "localhost"
    @AppStorage("ws_port") private var port = 9200
    @State private var testState: TestState = .idle
    @State private var showDeleteAlert = false
    @State private var isEmailConnected = false
    @State private var connectedEmail = ""
    @State private var triggerRuleCount = 0

    enum TestState {
        case idle
        case testing
        case success
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                emailSection
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

    private var emailSection: some View {
        Section {
            NavigationLink {
                EmailSettingsView()
            } label: {
                HStack(spacing: LoveMeTheme.md) {
                    Image(systemName: "envelope.fill")
                        .font(.toolTitle)
                        .foregroundStyle(.trust)
                        .frame(width: 20)
                    Text("Email")
                        .font(.chatMessage)
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    if isEmailConnected {
                        HStack(spacing: LoveMeTheme.sm) {
                            Circle()
                                .fill(Color.sageGreen)
                                .frame(width: LoveMeTheme.connectionDotSize,
                                       height: LoveMeTheme.connectionDotSize)
                            Text(connectedEmail)
                                .font(.toolDetail)
                                .foregroundStyle(.trust)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        Text("Not connected")
                            .font(.toolDetail)
                            .foregroundStyle(.trust)
                    }
                }
            }
            .frame(minHeight: LoveMeTheme.minTouchTarget)
            .listRowBackground(Color.surface)
            .accessibilityLabel("Email settings, \(isEmailConnected ? "connected as \(connectedEmail)" : "not connected")")

            NavigationLink {
                EmailTriggersView()
            } label: {
                HStack(spacing: LoveMeTheme.md) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.toolTitle)
                        .foregroundStyle(.trust)
                        .frame(width: 20)
                    Text("Email Rules")
                        .font(.chatMessage)
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    if triggerRuleCount > 0 {
                        Text("\(triggerRuleCount)")
                            .font(.toolDetail)
                            .foregroundStyle(.trust)
                            .monospacedDigit()
                    }
                }
            }
            .frame(minHeight: LoveMeTheme.minTouchTarget)
            .listRowBackground(Color.surface)
            .accessibilityLabel("Email rules, \(triggerRuleCount) active")
        } header: {
            Text("EMAIL")
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
            HStack(spacing: LoveMeTheme.sm) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.trust)
                Text("Testing...")
                    .foregroundStyle(.trust)
            }

        case .success:
            HStack(spacing: LoveMeTheme.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.sageGreen)
                Text("Connected")
                    .foregroundStyle(.sageGreen)
            }

        case .failed(let error):
            VStack(spacing: LoveMeTheme.xs) {
                HStack(spacing: LoveMeTheme.sm) {
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

    // MARK: - Actions

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
