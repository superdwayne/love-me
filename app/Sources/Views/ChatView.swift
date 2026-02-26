import SwiftUI

struct ChatView: View {
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(WebSocketClient.self) private var webSocket
    @State private var showSettings = false
    @State private var isNearBottom = true
    @State private var showNewMessagesPill = false
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Connection banner
                if webSocket.connectionState == .disconnected {
                    ConnectionBanner()
                        .zIndex(Double(ZLayer.banner.rawValue))
                }

                // Messages or empty state
                if chatVM.messages.isEmpty {
                    EmptyStateView()
                        .frame(maxHeight: .infinity)
                } else {
                    messageList
                }

                // Input bar
                InputBar()
            }

            // "New messages" pill
            if showNewMessagesPill {
                newMessagesPill
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: LoveMeTheme.sm) {
                    connectionDot
                    Text("love.Me")
                        .font(.navTitle)
                        .foregroundStyle(.textPrimary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.textSecondary)
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Subviews

    private var connectionDot: some View {
        Circle()
            .fill(connectionDotColor)
            .frame(width: LoveMeTheme.connectionDotSize,
                   height: LoveMeTheme.connectionDotSize)
            .accessibilityLabel(connectionStatusLabel)
    }

    private var connectionDotColor: Color {
        switch webSocket.connectionState {
        case .connected: return .sageGreen
        case .connecting: return .amberGlow
        case .disconnected: return .softRed
        }
    }

    private var connectionStatusLabel: String {
        switch webSocket.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return "Disconnected"
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(chatVM.messages.enumerated()), id: \.element.id) { index, message in
                        let prevMessage: Message? = index > 0 ? chatVM.messages[index - 1] : nil
                        let spacing = spacingBefore(message: message, previous: prevMessage)

                        VStack(spacing: 0) {
                            if message.role == .assistant {
                                // Thinking panel
                                if message.thinkingContent != nil {
                                    ThinkingPanel(message: message)
                                        .padding(.horizontal, LoveMeTheme.chatHorizontalPadding)
                                        .padding(.top, spacing)
                                        .padding(.bottom, LoveMeTheme.xs)
                                }

                                // Tool cards
                                ForEach(message.toolCalls) { toolCall in
                                    ToolCard(toolCall: toolCall)
                                        .padding(.horizontal, LoveMeTheme.chatHorizontalPadding)
                                        .padding(.bottom, LoveMeTheme.xs)
                                }
                            }

                            MessageBubble(message: message)
                                .padding(.horizontal, LoveMeTheme.chatHorizontalPadding)
                                .padding(.top, message.thinkingContent == nil && message.toolCalls.isEmpty ? spacing : LoveMeTheme.xs)
                        }
                        .id(message.id)
                    }

                    // Bottom anchor
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.vertical, LoveMeTheme.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chatVM.messages.count) { _, _ in
                if isNearBottom {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                } else {
                    showNewMessagesPill = true
                }
            }
            .onAppear {
                scrollProxy = proxy
            }
        }
    }

    private var newMessagesPill: some View {
        VStack {
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    scrollProxy?.scrollTo("bottom", anchor: .bottom)
                }
                showNewMessagesPill = false
                isNearBottom = true
            } label: {
                Text("New messages")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.textPrimary)
                    .padding(.horizontal, LoveMeTheme.md)
                    .padding(.vertical, LoveMeTheme.sm)
                    .background(.surfaceElevated)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
            .padding(.bottom, 80)
            .accessibilityLabel("Scroll to new messages")
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(Double(ZLayer.overlay.rawValue))
    }

    // MARK: - Helpers

    private func spacingBefore(message: Message, previous: Message?) -> CGFloat {
        guard let prev = previous else { return 0 }
        return prev.role == message.role
            ? LoveMeTheme.sameAuthorSpacing
            : LoveMeTheme.differentAuthorSpacing
    }
}
