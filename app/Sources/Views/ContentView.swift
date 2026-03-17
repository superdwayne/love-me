import SwiftUI

struct ContentView: View {
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(ConversationListViewModel.self) private var conversationListVM
    @Environment(WorkflowViewModel.self) private var workflowVM
    @Environment(EmailViewModel.self) private var emailVM
    @Environment(AmbientListeningViewModel.self) private var ambientVM
    @Environment(AgentPlanViewModel.self) private var agentPlanVM
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var selectedConversation: String?
    @State private var selectedTab: AppTab = .chat

    enum AppTab: String {
        case chat
        case workflows
        case agentMail
    }

    private var pendingApprovalCount: Int {
        emailVM.pendingApprovals.filter { $0.isPending }.count
    }

    private var pillTabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabItems, id: \.tab) { item in
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedTab = item.tab
                    }
                } label: {
                    VStack(spacing: 2) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: item.icon)
                                .font(.system(size: 18, weight: .medium))

                            if item.tab == .agentMail && pendingApprovalCount > 0 {
                                Text("\(pendingApprovalCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.error)
                                    .clipShape(Capsule())
                                    .offset(x: 10, y: -6)
                            }
                        }

                        Text(item.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == item.tab ? .coral : .textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Color.divider.frame(height: 0.5)
        }
    }

    private var tabItems: [(tab: AppTab, icon: String, label: String)] {
        [
            (.chat, "bubble.left.and.bubble.right", "Chat"),
            (.workflows, "bolt.fill", "Workflows"),
            (.agentMail, "envelope.fill", "Mail"),
        ]
    }

    var body: some View {
        if !hasSeenWelcome {
            WelcomeView()
        } else {
        ZStack(alignment: .bottom) {
            // Content area
            Group {
                switch selectedTab {
                case .chat:
                    NavigationSplitView {
                        ConversationListView(selection: $selectedConversation)
                            .safeAreaInset(edge: .bottom) {
                                Color.clear.frame(height: 60)
                            }
                    } detail: {
                        ChatView()
                            .safeAreaInset(edge: .bottom) {
                                Color.clear.frame(height: 60)
                                    .allowsHitTesting(false)
                            }
                    }
                    .onChange(of: selectedConversation) { _, newValue in
                        if let id = newValue, id != chatVM.currentConversationId {
                            chatVM.loadConversation(id)
                        }
                    }
                case .workflows:
                    NavigationStack {
                        WorkflowListView()
                    }
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 60)
                            .allowsHitTesting(false)
                    }
                case .agentMail:
                    NavigationStack {
                        AgentMailTabView()
                    }
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 60)
                            .allowsHitTesting(false)
                    }
                }
            }
            .tint(.heart)

            // Floating pill tab bar
            pillTabBar
                .padding(.bottom, 4)
        }
        .overlay {
            if ambientVM.isListening || !ambientVM.suggestions.isEmpty {
                AmbientListeningOverlay()
                    .zIndex(-1)
            }
        }
        .onChange(of: emailVM.navigateToConversationId) { _, conversationId in
            guard let conversationId else { return }
            selectedTab = .chat
            selectedConversation = conversationId
            chatVM.loadConversation(conversationId)
            emailVM.navigateToConversationId = nil
        }
        .sheet(isPresented: Binding(
            get: { agentPlanVM.showPlanReview },
            set: { agentPlanVM.showPlanReview = $0 }
        )) {
            PlanReviewSheet()
        }
        .fullScreenCover(isPresented: Binding(
            get: { agentPlanVM.isExecuting },
            set: { newValue in
                if !newValue { agentPlanVM.dismissExecution() }
            }
        )) {
            AgentDashboardView()
        }
        } // else
    }
}

// MARK: - Agent Mail Tab

struct AgentMailTabView: View {
    @Environment(EmailViewModel.self) private var emailVM
    @Environment(WebSocketClient.self) private var webSocket
    @State private var showSettings = false

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
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
            HStack(spacing: SolaceTheme.md) {
                ZStack {
                    Circle()
                        .fill(emailVM.isEmailConnected ? Color.sageGreen.opacity(0.15) : Color.textSecondary.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: emailVM.isEmailConnected ? "envelope.open.fill" : "envelope.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(emailVM.isEmailConnected ? .sageGreen : .textSecondary)
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
                            .foregroundStyle(.textSecondary)
                    }
                }

                Spacer()

                if emailVM.isEmailConnected {
                    Circle()
                        .fill(Color.sageGreen)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, SolaceTheme.xs)
            .listRowBackground(Color.surface)
        }
    }

    // MARK: - Pending Approvals

    @ViewBuilder
    private var pendingApprovalsSection: some View {
        let approvals = emailVM.pendingApprovals.filter { $0.isPending || $0.isBuilding }
        if !approvals.isEmpty {
            Section {
                ForEach(approvals) { approval in
                    EmailApprovalView(
                        approval: approval,
                        onChat: { emailVM.openEmailChat(approvalId: approval.id) },
                        onAutoWorkflow: { emailVM.autoCreateWorkflow(approvalId: approval.id) },
                        onSaveAutoFlow: { emailVM.saveAutoFlow(approvalId: approval.id) },
                        onDismiss: { emailVM.dismissEmail(approvalId: approval.id) }
                    )
                    .listRowBackground(Color.surface)
                    .listRowInsets(EdgeInsets())
                }
            } header: {
                HStack {
                    Text("PENDING APPROVALS")
                        .font(.sectionHeader)
                        .foregroundStyle(.dusk)
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
                HStack(spacing: SolaceTheme.sm) {
                    Image(systemName: "tray")
                        .font(.system(size: 14))
                        .foregroundStyle(.textSecondary.opacity(0.5))
                    Text("No messages yet")
                        .font(.toolDetail)
                        .foregroundStyle(.textSecondary.opacity(0.7))
                }
                .frame(minHeight: SolaceTheme.minTouchTarget)
                .listRowBackground(Color.surface)
            } else {
                ForEach(emailVM.inboxMessages) { message in
                    NavigationLink {
                        EmailDetailView(messageId: message.id)
                    } label: {
                        HStack(spacing: SolaceTheme.md) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.coral)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.subject)
                                    .font(.chatMessage)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.textPrimary)
                                    .lineLimit(1)

                                Text(message.from)
                                    .font(.toolDetail)
                                    .foregroundStyle(.textSecondary)
                                    .lineLimit(1)

                                Text(message.preview)
                                    .font(.toolDetail)
                                    .foregroundStyle(.textSecondary.opacity(0.7))
                                    .lineLimit(1)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(relativeDate(message.date))
                                    .font(.timestamp)
                                    .foregroundStyle(.textSecondary)

                                if message.attachmentCount > 0 {
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.textSecondary.opacity(0.5))
                                }
                            }
                        }
                        .frame(minHeight: SolaceTheme.minTouchTarget)
                    }
                    .listRowBackground(Color.surface)
                }
            }
        } header: {
            Text("INBOX")
                .font(.sectionHeader)
                .foregroundStyle(.dusk)
                .tracking(1.2)
        }
    }

    // MARK: - Actions (connected)

    private var actionsSection: some View {
        Section {
            HStack(spacing: SolaceTheme.md) {
                Image(systemName: "tray.full.fill")
                    .font(.toolTitle)
                    .foregroundStyle(.textSecondary)
                    .frame(width: 20)
                Text("Emails Processed")
                    .font(.chatMessage)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("\(emailVM.emailsProcessed)")
                    .font(.toolTitle)
                    .foregroundStyle(.textSecondary)
                    .monospacedDigit()
            }
            .frame(minHeight: SolaceTheme.minTouchTarget)
            .listRowBackground(Color.surface)

            HStack(spacing: SolaceTheme.md) {
                Image(systemName: "clock.fill")
                    .font(.toolTitle)
                    .foregroundStyle(.textSecondary)
                    .frame(width: 20)
                Text("Last Poll")
                    .font(.chatMessage)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text(emailVM.lastPollTime ?? "Never")
                    .font(.toolDetail)
                    .foregroundStyle(.textSecondary)
            }
            .frame(minHeight: SolaceTheme.minTouchTarget)
            .listRowBackground(Color.surface)
        } header: {
            Text("ACTIVITY")
                .font(.sectionHeader)
                .foregroundStyle(.dusk)
                .tracking(1.2)
        }
    }

    private var navigationSection: some View {
        Section {
            NavigationLink {
                EmailSettingsView()
            } label: {
                HStack(spacing: SolaceTheme.md) {
                    Image(systemName: "gearshape.fill")
                        .font(.toolTitle)
                        .foregroundStyle(.textSecondary)
                        .frame(width: 20)
                    Text("Account Settings")
                        .font(.chatMessage)
                        .foregroundStyle(.textPrimary)
                }
            }
            .frame(minHeight: SolaceTheme.minTouchTarget)
            .listRowBackground(Color.surface)

            NavigationLink {
                EmailTriggersView()
            } label: {
                HStack(spacing: SolaceTheme.md) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.toolTitle)
                        .foregroundStyle(.textSecondary)
                        .frame(width: 20)
                    Text("Email Rules")
                        .font(.chatMessage)
                        .foregroundStyle(.textPrimary)
                }
            }
            .frame(minHeight: SolaceTheme.minTouchTarget)
            .listRowBackground(Color.surface)
        } header: {
            Text("MANAGE")
                .font(.sectionHeader)
                .foregroundStyle(.dusk)
                .tracking(1.2)
        }
    }

    // MARK: - Connect (not connected)

    @State private var apiKeyInput = ""
    @State private var inboxIdInput = "solace"

    private var connectSection: some View {
        Section {
            VStack(spacing: SolaceTheme.lg) {
                Image(systemName: "envelope.open")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.textSecondary.opacity(0.4))
                    .padding(.top, SolaceTheme.md)

                VStack(spacing: SolaceTheme.sm) {
                    Text("Connect Agent Mail")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text("Email briefs to your agent and auto-create workflows.")
                        .font(.chatMessage)
                        .foregroundStyle(.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: SolaceTheme.md) {
                    SecureField("API Key", text: $apiKeyInput)
                        .textContentType(.password)
                        .font(.chatMessage)
                        .padding(SolaceTheme.md)
                        .background(Color.appBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    TextField("Inbox ID", text: $inboxIdInput)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.chatMessage)
                        .padding(SolaceTheme.md)
                        .background(Color.appBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("\(inboxIdInput)@agentmail.to")
                        .font(.toolDetail)
                        .foregroundStyle(.textSecondary)
                }

                Button {
                    emailVM.connectAgentMail(apiKey: apiKeyInput, inboxId: inboxIdInput)
                } label: {
                    HStack(spacing: SolaceTheme.sm) {
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
                    .padding(.vertical, SolaceTheme.md)
                    .background(apiKeyInput.isEmpty ? Color.coral.opacity(0.3) : Color.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(emailVM.isConnecting || apiKeyInput.isEmpty)
                .padding(.bottom, SolaceTheme.md)
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
