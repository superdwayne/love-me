import SwiftUI

struct ContentView: View {
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(ConversationListViewModel.self) private var conversationListVM
    @Environment(WorkflowViewModel.self) private var workflowVM
    @Environment(EmailViewModel.self) private var emailVM
    @State private var selectedConversation: String?
    @State private var selectedTab: AppTab = .chat

    enum AppTab: String {
        case chat
        case workflows
        case agentMail
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Chat Tab
            NavigationSplitView {
                ConversationListView(selection: $selectedConversation)
            } detail: {
                ChatView()
            }
            .tint(.heart)
            .onChange(of: selectedConversation) { _, newValue in
                if let id = newValue, id != chatVM.currentConversationId {
                    chatVM.loadConversation(id)
                }
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(AppTab.chat)

            // Workflows Tab
            NavigationStack {
                WorkflowListView()
            }
            .tint(.heart)
            .tabItem {
                Label("Workflows", systemImage: "arrow.triangle.branch")
            }
            .tag(AppTab.workflows)

            // Agent Mail Tab
            NavigationStack {
                AgentMailTabView()
            }
            .tint(.heart)
            .tabItem {
                Label("Agent Mail", systemImage: "envelope.fill")
            }
            .tag(AppTab.agentMail)
        }
        .tint(.heart)
        .onChange(of: emailVM.navigateToConversationId) { _, conversationId in
            guard let conversationId else { return }
            selectedTab = .chat
            selectedConversation = conversationId
            chatVM.loadConversation(conversationId)
            emailVM.navigateToConversationId = nil
        }
    }
}

// MARK: - Agent Mail Tab

struct AgentMailTabView: View {
    @Environment(EmailViewModel.self) private var emailVM
    @Environment(WebSocketClient.self) private var webSocket

    var body: some View {
        List {
            connectionStatusSection
            if emailVM.isEmailConnected {
                pendingApprovalsSection
                inboxMessagesSection
                actionsSection
                navigationSection
            } else {
                connectSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationTitle("Agent Mail")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.trust)
                }
            }
        }
        .onAppear {
            emailVM.requestEmailStatus()
        }
        .refreshable {
            emailVM.requestInboxMessages()
        }
    }

    // MARK: - Connection Status

    private var connectionStatusSection: some View {
        Section {
            HStack(spacing: LoveMeTheme.md) {
                ZStack {
                    Circle()
                        .fill(emailVM.isEmailConnected ? Color.sageGreen.opacity(0.15) : Color.trust.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: emailVM.isEmailConnected ? "envelope.open.fill" : "envelope.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(emailVM.isEmailConnected ? .sageGreen : .trust)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if emailVM.isEmailConnected {
                        Text(emailVM.connectedEmail)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Connected")
                            .font(.system(size: 12))
                            .foregroundStyle(.sageGreen)
                    } else {
                        Text("Agent Mail")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.textPrimary)
                        Text("Not connected")
                            .font(.system(size: 12))
                            .foregroundStyle(.trust)
                    }
                }

                Spacer()

                if emailVM.isEmailConnected {
                    Circle()
                        .fill(Color.sageGreen)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, LoveMeTheme.xs)
            .listRowBackground(Color.surface)
        }
    }

    // MARK: - Pending Approvals

    @ViewBuilder
    private var pendingApprovalsSection: some View {
        let approvals = emailVM.pendingApprovals.filter { $0.isPending }
        if !approvals.isEmpty {
            Section {
                ForEach(approvals) { approval in
                    EmailApprovalView(
                        approval: approval,
                        onChat: { emailVM.openEmailChat(approvalId: approval.id) },
                        onAutoWorkflow: { emailVM.autoCreateWorkflow(approvalId: approval.id) },
                        onDismiss: { emailVM.dismissEmail(approvalId: approval.id) }
                    )
                    .listRowBackground(Color.surface)
                    .listRowInsets(EdgeInsets())
                }
            } header: {
                HStack {
                    Text("PENDING APPROVALS")
                        .font(.sectionHeader)
                        .foregroundStyle(.trust)
                        .tracking(1.2)
                    Spacer()
                    Text("\(approvals.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.heart)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Inbox Messages

    private var inboxMessagesSection: some View {
        Section {
            if emailVM.inboxMessages.isEmpty {
                HStack(spacing: LoveMeTheme.sm) {
                    Image(systemName: "tray")
                        .font(.system(size: 14))
                        .foregroundStyle(.trust.opacity(0.5))
                    Text("No messages yet")
                        .font(.toolDetail)
                        .foregroundStyle(.trust.opacity(0.7))
                }
                .frame(minHeight: LoveMeTheme.minTouchTarget)
                .listRowBackground(Color.surface)
            } else {
                ForEach(emailVM.inboxMessages) { message in
                    HStack(spacing: LoveMeTheme.md) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.trust)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.subject)
                                .font(.chatMessage)
                                .fontWeight(.medium)
                                .foregroundStyle(.textPrimary)
                                .lineLimit(1)

                            Text(message.from)
                                .font(.toolDetail)
                                .foregroundStyle(.trust)
                                .lineLimit(1)

                            Text(message.preview)
                                .font(.toolDetail)
                                .foregroundStyle(.trust.opacity(0.7))
                                .lineLimit(1)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(relativeDate(message.date))
                                .font(.timestamp)
                                .foregroundStyle(.trust)

                            if message.attachmentCount > 0 {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.trust.opacity(0.5))
                            }
                        }
                    }
                    .frame(minHeight: LoveMeTheme.minTouchTarget)
                    .listRowBackground(Color.surface)
                }
            }
        } header: {
            Text("INBOX")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    // MARK: - Actions (connected)

    private var actionsSection: some View {
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
                Text("\(emailVM.emailsProcessed)")
                    .font(.toolTitle)
                    .foregroundStyle(.trust)
                    .monospacedDigit()
            }
            .frame(minHeight: LoveMeTheme.minTouchTarget)
            .listRowBackground(Color.surface)

            HStack(spacing: LoveMeTheme.md) {
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
            .frame(minHeight: LoveMeTheme.minTouchTarget)
            .listRowBackground(Color.surface)
        } header: {
            Text("ACTIVITY")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    private var navigationSection: some View {
        Section {
            NavigationLink {
                EmailSettingsView()
            } label: {
                HStack(spacing: LoveMeTheme.md) {
                    Image(systemName: "gearshape.fill")
                        .font(.toolTitle)
                        .foregroundStyle(.trust)
                        .frame(width: 20)
                    Text("Account Settings")
                        .font(.chatMessage)
                        .foregroundStyle(.textPrimary)
                }
            }
            .frame(minHeight: LoveMeTheme.minTouchTarget)
            .listRowBackground(Color.surface)

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
                }
            }
            .frame(minHeight: LoveMeTheme.minTouchTarget)
            .listRowBackground(Color.surface)
        } header: {
            Text("MANAGE")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    // MARK: - Connect (not connected)

    @State private var apiKeyInput = ""
    @State private var inboxIdInput = "love.me"

    private var connectSection: some View {
        Section {
            VStack(spacing: LoveMeTheme.lg) {
                Image(systemName: "envelope.open")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.trust.opacity(0.4))
                    .padding(.top, LoveMeTheme.md)

                VStack(spacing: LoveMeTheme.sm) {
                    Text("Connect Agent Mail")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text("Email briefs to your agent and auto-create workflows.")
                        .font(.chatMessage)
                        .foregroundStyle(.trust)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: LoveMeTheme.md) {
                    SecureField("API Key", text: $apiKeyInput)
                        .textContentType(.password)
                        .font(.chatMessage)
                        .padding(LoveMeTheme.md)
                        .background(Color.appBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    TextField("Inbox ID", text: $inboxIdInput)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.chatMessage)
                        .padding(LoveMeTheme.md)
                        .background(Color.appBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("\(inboxIdInput)@agentmail.to")
                        .font(.toolDetail)
                        .foregroundStyle(.trust)
                }

                Button {
                    emailVM.connectAgentMail(apiKey: apiKeyInput, inboxId: inboxIdInput)
                } label: {
                    HStack(spacing: LoveMeTheme.sm) {
                        if emailVM.isConnecting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                            Text("Connecting...")
                        } else {
                            Image(systemName: "envelope.fill")
                            Text("Connect Agent Mail")
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LoveMeTheme.md)
                    .background(apiKeyInput.isEmpty ? Color.trust.opacity(0.3) : Color.heart)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(emailVM.isConnecting || apiKeyInput.isEmpty)
                .padding(.bottom, LoveMeTheme.md)
            }
            .listRowBackground(Color.surface)

            if let error = emailVM.authError {
                Text(error)
                    .font(.toolDetail)
                    .foregroundStyle(.softRed)
                    .listRowBackground(Color.surface)
            }
        }
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
