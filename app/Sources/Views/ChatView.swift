import SwiftUI

// MARK: - Scroll Position Tracking

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatView: View {
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(WebSocketClient.self) private var webSocket
    @State private var showSettings = false
    @State private var isNearBottom = true
    @State private var showNewMessagesPill = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var lastScrollTime: Date = .distantPast

    /// Threshold (in points) for considering the user "near bottom"
    private let nearBottomThreshold: CGFloat = 150

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

                // Search bar
                if chatVM.isSearchActive {
                    ChatSearchBar()
                        .transition(.move(edge: .top).combined(with: .opacity))
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
                HStack(spacing: SolaceTheme.sm) {
                    connectionDot
                    Text("Solace")
                        .font(.navTitle)
                        .foregroundStyle(.textPrimary)
                    if webSocket.connectionState == .connected {
                        Text(providerLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.trust.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.surfaceElevated.opacity(0.5))
                            .clipShape(Capsule())
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    chatVM.toggleSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.textSecondary)
                }
                .accessibilityLabel("Search messages")
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
            .frame(width: SolaceTheme.connectionDotSize,
                   height: SolaceTheme.connectionDotSize)
            .accessibilityLabel(connectionStatusLabel)
    }

    private var providerLabel: String {
        let provider = webSocket.activeProvider.lowercased()
        let model = webSocket.activeModel

        if model.isEmpty {
            return provider.capitalized
        }

        // Show a short, readable model name instead of the full ID
        let shortModel = Self.shortenModelName(model)
        return "\(provider.capitalized): \(shortModel)"
    }

    /// Convert full model IDs to readable short names
    private static func shortenModelName(_ model: String) -> String {
        let m = model.lowercased()
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        if m.contains("gpt-4o-mini") { return "GPT-4o Mini" }
        if m.contains("gpt-4o") { return "GPT-4o" }
        if m.contains("gpt-4") { return "GPT-4" }
        if m.contains("o3") { return "o3" }
        if m.contains("o1") { return "o1" }
        // For Ollama or unknown models, show as-is
        return model
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
                    ForEach(chatVM.messages) { message in
                        let prevMessage = previousMessage(before: message)
                        let spacing = spacingBefore(message: message, previous: prevMessage)

                        VStack(spacing: 0) {
                            if message.role == .user && message.attachments.contains(where: { !$0.isAudio }) {
                                // User attachment images (audio shown inside bubble)
                                attachmentImages(for: message)
                                    .padding(.horizontal, SolaceTheme.chatHorizontalPadding)
                                    .padding(.top, spacing)
                                    .padding(.bottom, SolaceTheme.xs)
                            }

                            if message.role == .assistant {
                                // Thinking panel
                                if message.thinkingContent != nil {
                                    ThinkingPanel(message: message)
                                        .padding(.horizontal, SolaceTheme.chatHorizontalPadding)
                                        .padding(.top, spacing)
                                        .padding(.bottom, SolaceTheme.xs)
                                }

                                // Tool cards
                                ForEach(message.toolCalls) { toolCall in
                                    ToolCard(toolCall: toolCall)
                                        .padding(.horizontal, SolaceTheme.chatHorizontalPadding)
                                        .padding(.bottom, SolaceTheme.xs)

                                    // Inline image preview from image-generating tools (e.g. Leonardo)
                                    if let imageURL = toolCall.imageURL,
                                       let url = chatVM.daemonImageURL(from: imageURL) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .empty:
                                                RoundedRectangle(cornerRadius: SolaceTheme.sm)
                                                    .fill(Color.surfaceElevated)
                                                    .frame(height: 200)
                                                    .overlay {
                                                        ProgressView()
                                                            .tint(.trust)
                                                    }
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fit)
                                                    .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
                                            case .failure:
                                                EmptyView()
                                            @unknown default:
                                                EmptyView()
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, SolaceTheme.chatHorizontalPadding)
                                        .padding(.bottom, SolaceTheme.xs)
                                    }
                                }
                            }

                            MessageBubble(message: message)
                                .padding(.horizontal, SolaceTheme.chatHorizontalPadding)
                                .padding(.top, message.thinkingContent == nil && message.toolCalls.isEmpty && message.attachments.isEmpty ? spacing : SolaceTheme.xs)
                        }
                        .id(message.id)
                    }

                    // Bottom anchor with scroll position detection
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("chatScroll")).minY
                            )
                    }
                    .frame(height: 1)
                    .id("bottom")
                }
                .padding(.vertical, SolaceTheme.lg)
            }
            .coordinateSpace(name: "chatScroll")
            .scrollDismissesKeyboard(.interactively)
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { bottomY in
                // bottomY is the Y position of the bottom anchor within the scroll view's
                // visible coordinate space. When it's close to or below the visible height,
                // the user is near the bottom.
                // The scroll view's visible area starts at 0 and extends to its height.
                // If bottomY <= scrollViewHeight + threshold, user is near bottom.
                // Since we're in the scroll view's coordinate space, a small bottomY means
                // the bottom anchor is visible (near bottom). We use a heuristic:
                // the coordinate space origin is at the top of the visible scroll area,
                // so when scrolled to bottom, bottomY ≈ visible height of scroll view.
                // We don't have the exact scroll view height, but we can detect changes:
                // when user scrolls up, bottomY increases (anchor moves further below viewport).
                // A practical approach: track whether the anchor is within viewport bounds.

                // Use UIScreen as a reasonable proxy for max visible height
                let screenHeight = UIScreen.main.bounds.height
                let newIsNearBottom = bottomY < screenHeight + nearBottomThreshold

                if newIsNearBottom != isNearBottom {
                    isNearBottom = newIsNearBottom
                    if newIsNearBottom {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showNewMessagesPill = false
                        }
                    }
                }
            }
            .onChange(of: chatVM.messages.count) { _, _ in
                if isNearBottom {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showNewMessagesPill = true
                    }
                }
            }
            .onChange(of: chatVM.isStreaming) { _, streaming in
                if streaming && isNearBottom {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: streamingContentLength) { _, _ in
                if isNearBottom {
                    let now = Date()
                    guard now.timeIntervalSince(lastScrollTime) >= 0.1 else { return }
                    lastScrollTime = now
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: chatVM.currentMatchMessageId) { _, messageId in
                if let messageId {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(messageId, anchor: .center)
                    }
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
                    .padding(.horizontal, SolaceTheme.md)
                    .padding(.vertical, SolaceTheme.sm)
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

    /// Tracks streaming content length to drive auto-scroll during generation
    private var streamingContentLength: Int {
        guard let last = chatVM.messages.last, last.role == .assistant else { return 0 }
        return last.content.count + last.toolCalls.count
    }

    // MARK: - Attachment Images

    @ViewBuilder
    private func attachmentImages(for message: Message) -> some View {
        HStack(alignment: .top, spacing: SolaceTheme.sm) {
            Spacer()
            ForEach(message.attachments.filter { !$0.isAudio }) { attachment in
                if let thumbData = attachment.thumbnailData,
                   let uiImage = UIImage(data: thumbData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: 150, maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
                } else if let urlStr = attachment.imageURL,
                          let url = chatVM.daemonImageURL(from: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: SolaceTheme.sm)
                                .fill(Color.surfaceElevated)
                                .frame(width: 150, height: 150)
                                .overlay { ProgressView().tint(.trust) }
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: 150, maxHeight: 150)
                                .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
                        case .failure:
                            RoundedRectangle(cornerRadius: SolaceTheme.sm)
                                .fill(Color.surfaceElevated)
                                .frame(width: 100, height: 100)
                                .overlay {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .foregroundStyle(.textSecondary)
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func previousMessage(before message: Message) -> Message? {
        guard let idx = chatVM.messages.firstIndex(where: { $0.id == message.id }),
              idx > 0 else { return nil }
        return chatVM.messages[idx - 1]
    }

    private func spacingBefore(message: Message, previous: Message?) -> CGFloat {
        guard let prev = previous else { return 0 }
        return prev.role == message.role
            ? SolaceTheme.sameAuthorSpacing
            : SolaceTheme.differentAuthorSpacing
    }
}
