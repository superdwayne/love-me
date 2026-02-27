import SwiftUI

struct EmailSettingsView: View {
    @Environment(WebSocketClient.self) private var webSocket
    @Environment(\.dismiss) private var dismiss

    @State private var isEmailConnected = false
    @State private var connectedEmail = ""
    @State private var lastPollTime: String?
    @State private var emailsProcessed = 0
    @State private var pollingInterval = 60
    @State private var showDisconnectAlert = false
    @State private var isConnecting = false

    private let pollingOptions: [(label: String, seconds: Int)] = [
        ("1 min", 60),
        ("2 min", 120),
        ("5 min", 300),
        ("15 min", 900),
    ]

    var body: some View {
        List {
            statusSection
            connectionSection
            if isEmailConnected {
                statsSection
                pollingSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationTitle("Email")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .animation(.easeInOut(duration: LoveMeTheme.springDuration), value: isEmailConnected)
        .onAppear {
            requestEmailStatus()
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack {
                Text("Status")
                    .font(.chatMessage)
                    .foregroundStyle(.textPrimary)
                Spacer()
                if isEmailConnected {
                    HStack(spacing: LoveMeTheme.sm) {
                        Circle()
                            .fill(Color.sageGreen)
                            .frame(width: LoveMeTheme.connectionDotSize,
                                   height: LoveMeTheme.connectionDotSize)
                        Text("Connected")
                            .font(.toolTitle)
                            .foregroundStyle(.sageGreen)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    Text("Not connected")
                        .font(.toolTitle)
                        .foregroundStyle(.trust)
                }
            }
            .frame(minHeight: LoveMeTheme.minTouchTarget)
            .listRowBackground(Color.surface)
            .accessibilityLabel("Email status: \(isEmailConnected ? "Connected" : "Not connected")")

            if isEmailConnected {
                HStack {
                    Text("Account")
                        .font(.chatMessage)
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Text(connectedEmail)
                        .font(.toolDetail)
                        .foregroundStyle(.trust)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(minHeight: LoveMeTheme.minTouchTarget)
                .listRowBackground(Color.surface)
                .accessibilityLabel("Connected account: \(connectedEmail)")
            }
        } header: {
            Text("ACCOUNT")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    private var connectionSection: some View {
        Section {
            if isEmailConnected {
                Button(role: .destructive) {
                    showDisconnectAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Disconnect Gmail")
                            .font(.chatMessage)
                            .foregroundStyle(.softRed)
                        Spacer()
                    }
                }
                .frame(minHeight: LoveMeTheme.minTouchTarget)
                .listRowBackground(Color.surface)
                .accessibilityLabel("Disconnect Gmail account")
                .alert("Disconnect Email", isPresented: $showDisconnectAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Disconnect", role: .destructive) {
                        disconnectEmail()
                    }
                } message: {
                    Text("Are you sure you want to disconnect your Gmail account? Email triggers will stop working.")
                }
            } else {
                Button {
                    connectGmail()
                } label: {
                    HStack {
                        Spacer()
                        connectButtonLabel
                        Spacer()
                    }
                }
                .frame(minHeight: LoveMeTheme.minTouchTarget)
                .listRowBackground(Color.surface)
                .accessibilityLabel(isConnecting ? "Connecting to Gmail" : "Connect Gmail account")
            }
        } header: {
            Text("CONNECTION")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    @ViewBuilder
    private var connectButtonLabel: some View {
        if isConnecting {
            HStack(spacing: LoveMeTheme.sm) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.trust)
                Text("Connecting...")
                    .font(.chatMessage)
                    .foregroundStyle(.trust)
            }
        } else {
            HStack(spacing: LoveMeTheme.sm) {
                Image(systemName: "envelope.fill")
                Text("Connect Gmail")
                    .font(.chatMessage)
            }
            .foregroundStyle(.heart)
        }
    }

    private var statsSection: some View {
        Section {
            HStack(spacing: LoveMeTheme.md) {
                Image(systemName: "tray.full.fill")
                    .font(.toolTitle)
                    .foregroundStyle(.trust)
                    .frame(width: 20)
                Text("Emails Processed")
                    .font(.chatMessage)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("\(emailsProcessed)")
                    .font(.toolTitle)
                    .foregroundStyle(.trust)
                    .monospacedDigit()
            }
            .frame(minHeight: LoveMeTheme.minTouchTarget)
            .listRowBackground(Color.surface)
            .accessibilityLabel("Emails processed: \(emailsProcessed)")

            HStack(spacing: LoveMeTheme.md) {
                Image(systemName: "clock.fill")
                    .font(.toolTitle)
                    .foregroundStyle(.trust)
                    .frame(width: 20)
                Text("Last Poll")
                    .font(.chatMessage)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text(lastPollTime ?? "Never")
                    .font(.toolDetail)
                    .foregroundStyle(.trust)
            }
            .frame(minHeight: LoveMeTheme.minTouchTarget)
            .listRowBackground(Color.surface)
            .accessibilityLabel("Last poll: \(lastPollTime ?? "Never")")
        } header: {
            Text("ACTIVITY")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    private var pollingSection: some View {
        Section {
            Picker(selection: $pollingInterval) {
                ForEach(pollingOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            } label: {
                HStack(spacing: LoveMeTheme.md) {
                    Image(systemName: "arrow.clockwise")
                        .font(.toolTitle)
                        .foregroundStyle(.trust)
                        .frame(width: 20)
                    Text("Check Every")
                        .font(.chatMessage)
                        .foregroundStyle(.textPrimary)
                }
            }
            .tint(.trust)
            .frame(minHeight: LoveMeTheme.minTouchTarget)
            .listRowBackground(Color.surface)
            .accessibilityLabel("Polling interval")
            .onChange(of: pollingInterval) { _, newValue in
                updatePollingInterval(newValue)
            }
        } header: {
            Text("POLLING")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        } footer: {
            Text("How often love.Me checks for new emails.")
                .font(.toolDetail)
                .foregroundStyle(.trust)
                .padding(.top, LoveMeTheme.xs)
        }
    }

    // MARK: - Actions

    private func requestEmailStatus() {
        webSocket.send(WSMessage(type: WSMessageType.emailStatus))
    }

    private func connectGmail() {
        isConnecting = true
        HapticManager.messageSent()
        webSocket.send(WSMessage(type: WSMessageType.emailAuthStart))

        // The daemon will respond with an auth URL via a message.
        // The app's message router should handle opening it in Safari
        // and updating isConnecting when the auth flow completes.
    }

    private func disconnectEmail() {
        HapticManager.connectionLost()
        webSocket.send(WSMessage(type: WSMessageType.emailAuthDisconnect))
        withAnimation(.easeInOut(duration: LoveMeTheme.springDuration)) {
            isEmailConnected = false
            connectedEmail = ""
            lastPollTime = nil
            emailsProcessed = 0
        }
    }

    private func updatePollingInterval(_ seconds: Int) {
        webSocket.send(WSMessage(
            type: WSMessageType.emailUpdatePolling,
            metadata: ["intervalSeconds": .int(seconds)]
        ))
    }

    // MARK: - Message Handling

    /// Called by the app's message router when email status messages arrive.
    func handleEmailStatus(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }

        if let connected = meta["connected"]?.boolValue {
            isEmailConnected = connected
        }
        if let email = meta["email"]?.stringValue {
            connectedEmail = email
        }
        if let lastPoll = meta["lastPollTime"]?.stringValue {
            lastPollTime = lastPoll
        }
        if let processed = meta["emailsProcessed"]?.intValue {
            emailsProcessed = processed
        }
        if let interval = meta["pollingInterval"]?.intValue {
            pollingInterval = interval
        }

        // Clear connecting state if auth completed
        if isConnecting && isEmailConnected {
            isConnecting = false
            HapticManager.connectionEstablished()
        }
    }

    /// Called when the daemon returns an auth URL to open in Safari.
    func handleAuthURL(_ msg: WSMessage) {
        guard let urlString = msg.metadata?["url"]?.stringValue,
              let url = URL(string: urlString) else {
            isConnecting = false
            HapticManager.toolError()
            return
        }

        UIApplication.shared.open(url)
    }
}
