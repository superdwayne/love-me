import SwiftUI

struct EmailSettingsView: View {
    @Environment(EmailViewModel.self) private var emailVM
    @Environment(\.dismiss) private var dismiss

    @State private var showDisconnectAlert = false

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
            if emailVM.isEmailConnected {
                statsSection
                pollingSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationTitle("Agent Mail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .animation(.easeInOut(duration: SolaceTheme.springDuration), value: emailVM.isEmailConnected)
        .onAppear {
            emailVM.requestEmailStatus()
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
                if emailVM.isEmailConnected {
                    HStack(spacing: SolaceTheme.sm) {
                        Circle()
                            .fill(Color.sageGreen)
                            .frame(width: SolaceTheme.connectionDotSize,
                                   height: SolaceTheme.connectionDotSize)
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
            .frame(minHeight: SolaceTheme.minTouchTarget)
            .listRowBackground(Color.surface)
            .accessibilityLabel("Email status: \(emailVM.isEmailConnected ? "Connected" : "Not connected")")

            if emailVM.isEmailConnected {
                HStack {
                    Text("Account")
                        .font(.chatMessage)
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Text(emailVM.connectedEmail)
                        .font(.toolDetail)
                        .foregroundStyle(.trust)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(minHeight: SolaceTheme.minTouchTarget)
                .listRowBackground(Color.surface)
                .accessibilityLabel("Connected account: \(emailVM.connectedEmail)")
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
            if emailVM.isEmailConnected {
                Button(role: .destructive) {
                    showDisconnectAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Disconnect Agent Mail")
                            .font(.chatMessage)
                            .foregroundStyle(.softRed)
                        Spacer()
                    }
                }
                .frame(minHeight: SolaceTheme.minTouchTarget)
                .listRowBackground(Color.surface)
                .accessibilityLabel("Disconnect Agent Mail account")
                .alert("Disconnect Agent Mail", isPresented: $showDisconnectAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Disconnect", role: .destructive) {
                        emailVM.disconnectEmail()
                    }
                } message: {
                    Text("Are you sure you want to disconnect Agent Mail? Email triggers and auto-workflows will stop working.")
                }
            }
        } header: {
            Text("CONNECTION")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    private var statsSection: some View {
        Section {
            HStack(spacing: SolaceTheme.md) {
                Image(systemName: "tray.full.fill")
                    .font(.toolTitle)
                    .foregroundStyle(.trust)
                    .frame(width: 20)
                Text("Emails Processed")
                    .font(.chatMessage)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("\(emailVM.emailsProcessed)")
                    .font(.toolTitle)
                    .foregroundStyle(.trust)
                    .monospacedDigit()
            }
            .frame(minHeight: SolaceTheme.minTouchTarget)
            .listRowBackground(Color.surface)
            .accessibilityLabel("Emails processed: \(emailVM.emailsProcessed)")

            HStack(spacing: SolaceTheme.md) {
                Image(systemName: "clock.fill")
                    .font(.toolTitle)
                    .foregroundStyle(.trust)
                    .frame(width: 20)
                Text("Last Poll")
                    .font(.chatMessage)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text(emailVM.lastPollTime ?? "Never")
                    .font(.toolDetail)
                    .foregroundStyle(.trust)
            }
            .frame(minHeight: SolaceTheme.minTouchTarget)
            .listRowBackground(Color.surface)
            .accessibilityLabel("Last poll: \(emailVM.lastPollTime ?? "Never")")
        } header: {
            Text("ACTIVITY")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    private var pollingSection: some View {
        Section {
            @Bindable var vm = emailVM
            Picker(selection: $vm.pollingInterval) {
                ForEach(pollingOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            } label: {
                HStack(spacing: SolaceTheme.md) {
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
            .frame(minHeight: SolaceTheme.minTouchTarget)
            .listRowBackground(Color.surface)
            .accessibilityLabel("Polling interval")
            .onChange(of: emailVM.pollingInterval) { _, newValue in
                emailVM.updatePollingInterval(newValue)
            }
        } header: {
            Text("POLLING")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        } footer: {
            Text("How often Solace checks for new emails.")
                .font(.toolDetail)
                .foregroundStyle(.trust)
                .padding(.top, SolaceTheme.xs)
        }
    }
}
