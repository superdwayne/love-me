import SwiftUI

// MARK: - Conversation Block Model

struct ConversationBlock: Identifiable {
    let id: String
    let userMessage: Message?
    let assistantMessage: Message?

    /// Groups a flat message list into conversation blocks.
    /// Pairs consecutive user+assistant messages; standalone messages get their own block.
    static func groupMessages(_ messages: [Message]) -> [ConversationBlock] {
        var blocks: [ConversationBlock] = []
        var i = 0

        while i < messages.count {
            let msg = messages[i]

            if msg.role == .user {
                // Check if next message is assistant
                if i + 1 < messages.count && messages[i + 1].role == .assistant {
                    let assistant = messages[i + 1]
                    blocks.append(ConversationBlock(
                        id: msg.id,
                        userMessage: msg,
                        assistantMessage: assistant
                    ))
                    i += 2
                } else {
                    // Standalone user (awaiting response)
                    blocks.append(ConversationBlock(
                        id: msg.id,
                        userMessage: msg,
                        assistantMessage: nil
                    ))
                    i += 1
                }
            } else {
                // Orphan assistant message
                blocks.append(ConversationBlock(
                    id: msg.id,
                    userMessage: nil,
                    assistantMessage: msg
                ))
                i += 1
            }
        }

        return blocks
    }

    /// Returns the message ID that search should scroll to for this block.
    func containsMessage(id: String) -> Bool {
        userMessage?.id == id || assistantMessage?.id == id
    }
}

// MARK: - MessageBubbleInline

/// Lightweight inline message content renderer (rendered markdown + voice notes).
/// Used by ConversationBlockView where the outer chrome (padding, background, shape) is applied externally.
private struct MessageBubbleInline: View {
    let message: Message
    @Environment(ChatViewModel.self) private var chatVM
    @State private var renderedContent: AttributedString = AttributedString()
    @State private var lastRenderTime: Date = .distantPast

    private var audioAttachments: [MessageAttachment] {
        message.attachments.filter { $0.isAudio }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            // Voice note players
            ForEach(audioAttachments) { attachment in
                if let audioData = attachment.thumbnailData, !audioData.isEmpty {
                    VoiceNotePlayerView(
                        audioData: audioData,
                        duration: attachment.audioDuration ?? 0,
                        isUserMessage: message.role == .user
                    )
                } else if let urlStr = attachment.imageURL,
                          let url = chatVM.daemonImageURL(from: urlStr) {
                    RemoteVoiceNoteView(
                        url: url,
                        duration: attachment.audioDuration ?? 0,
                        isUserMessage: message.role == .user
                    )
                }
            }

            // Text content
            if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(renderedContent)
                    .font(.chatMessage)
                    .foregroundStyle(message.role == .user ? .dusk : .textPrimary)
                    .onChange(of: message.content) { _, newContent in
                        throttleRender(newContent)
                    }
                    .onChange(of: message.isStreaming) { _, streaming in
                        if !streaming { renderWithSearch(message.content) }
                    }
                    .onAppear { renderWithSearch(message.content) }
                    .onChange(of: chatVM.searchQuery) { _, _ in
                        renderWithSearch(message.content)
                    }
                    .onChange(of: chatVM.currentMatchIndex) { _, _ in
                        renderWithSearch(message.content)
                    }
            } else if message.isStreaming {
                // Streaming dots
                HStack(spacing: SolaceTheme.xs) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.trust)
                            .frame(width: 6, height: 6)
                    }
                }

                // Link previews (assistant only, after streaming)
            }
            if message.role == .assistant && !message.isStreaming {
                LinkPreviewContainer(
                    messageContent: message.content,
                    isStreaming: message.isStreaming
                )
            }
        }
    }

    private func throttleRender(_ content: String) {
        guard message.isStreaming else {
            renderWithSearch(content)
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastRenderTime) >= 0.1 else { return }
        renderWithSearch(content)
        lastRenderTime = now
    }

    private func renderWithSearch(_ content: String) {
        if chatVM.isSearchActive && !chatVM.searchQuery.isEmpty {
            let isActive = chatVM.currentMatchMessageId == message.id
            renderedContent = MarkdownRenderer.render(content, highlighting: chatVM.searchQuery, isActiveMatch: isActive)
        } else {
            renderedContent = MarkdownRenderer.render(content)
        }
        lastRenderTime = Date()
    }
}

// MARK: - ConversationBlockView

struct ConversationBlockView: View {
    let block: ConversationBlock
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0
    @State private var didTriggerReply = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // User message — open layout, no card wrapping
            if let userMsg = block.userMessage {
                userSection(userMsg)
            }

            // Assistant response — open layout beneath
            if let assistantMsg = block.assistantMessage {
                assistantSection(assistantMsg)
            }
        }
        .padding(.vertical, 8)
        .opacity(appeared ? 1.0 : 0.0)
        .offset(y: appeared ? 0 : 8)
        .offset(x: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    guard value.translation.width > 0 else { return }
                    dragOffset = min(value.translation.width * 0.4, 60)
                    if dragOffset > 40 && !didTriggerReply {
                        didTriggerReply = true
                        HapticManager.longPress()
                    }
                }
                .onEnded { _ in
                    if didTriggerReply, let msg = block.userMessage ?? block.assistantMessage {
                        chatVM.quoteReply(msg)
                    }
                    withAnimation(.spring(duration: 0.25)) {
                        dragOffset = 0
                    }
                    didTriggerReply = false
                }
        )
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(duration: SolaceTheme.blockEntranceDuration)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - User Section (open, no card — just the message with a soft background)

    @ViewBuilder
    private func userSection(_ message: Message) -> some View {
        VStack(alignment: .trailing, spacing: SolaceTheme.sm) {
            // Attachment images (non-audio)
            if message.attachments.contains(where: { !$0.isAudio }) {
                attachmentImages(for: message)
            }

            // User bubble — right-aligned, soft lavender pill
            VStack(alignment: .trailing, spacing: SolaceTheme.xs) {
                MessageBubbleInline(message: message)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.coral.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // Metadata
                HStack(spacing: SolaceTheme.sm) {
                    if message.sendFailed {
                        Text("Not sent. Tap to retry.")
                            .font(.captionSmall)
                            .foregroundStyle(.error)
                            .onTapGesture {
                                chatVM.retryMessage(message)
                            }
                    }

                    if message.isEdited {
                        Text("edited")
                            .font(.system(size: 10))
                            .foregroundStyle(.dusk.opacity(0.5))
                    }

                    Text(formattedTimestamp(message.timestamp))
                        .font(.timestamp)
                        .foregroundStyle(.dusk.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contextMenu {
            Button {
                chatVM.copyMessageContent(message)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if !chatVM.isStreaming {
                Button {
                    chatVM.startEditing(message)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }

            Button {
                chatVM.retryMessage(message)
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }

            Button(role: .destructive) {
                chatVM.deleteMessage(message)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Assistant Section (open, with identity header)

    @ViewBuilder
    private func assistantSection(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: SolaceTheme.md) {
            // Assistant identity
            HStack(spacing: SolaceTheme.sm) {
                // Avatar circle
                ZStack {
                    Circle()
                        .fill(Color.coral.opacity(0.08))
                        .frame(width: 28, height: 28)

                    SpiritGuideView(size: .inline)
                        .frame(width: 16, height: 16)
                }

                Text("Solace")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.dusk)

                // Status pill
                if message.isStreaming || message.isThinkingStreaming || !message.toolCalls.filter({ $0.status == .running }).isEmpty {
                    statusPill(message)
                }
            }

            // Thinking panel
            if message.thinkingContent != nil {
                ThinkingPanel(message: message)
            }

            // Tool cards
            ForEach(message.toolCalls) { toolCall in
                ToolCard(toolCall: toolCall)

                // Inline image preview from image-generating tools
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
                                        .tint(.dusk)
                                }
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        case .failure:
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Assistant message content — left-aligned, on a white/surface card
            MessageBubbleInline(message: message)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.03), radius: 8, y: 2)

            // Timestamp
            Text(formattedTimestamp(message.timestamp))
                .font(.timestamp)
                .foregroundStyle(.dusk.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button {
                chatVM.copyMessageContent(message)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                chatVM.deleteMessage(message)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Status Pill

    @ViewBuilder
    private func statusPill(_ message: Message) -> some View {
        let runningTools = message.toolCalls.filter { $0.status == .running }

        let statusText: String = {
            if !runningTools.isEmpty {
                let count = runningTools.count
                return count == 1
                    ? "Using \(runningTools[0].toolName)..."
                    : "Using \(count) tools..."
            } else if message.isThinkingStreaming {
                return "Thinking..."
            } else if message.isStreaming {
                return "Responding..."
            }
            return ""
        }()

        Text(statusText)
            .font(.small)
            .foregroundStyle(.coral)
            .padding(.horizontal, SolaceTheme.sm)
            .padding(.vertical, 3)
            .background(Color.coral.opacity(0.08))
            .clipShape(Capsule())
    }

    // MARK: - Attachment Images

    @ViewBuilder
    private func attachmentImages(for message: Message) -> some View {
        HStack(alignment: .top, spacing: SolaceTheme.sm) {
            ForEach(message.attachments.filter { !$0.isAudio }) { attachment in
                if let thumbData = attachment.thumbnailData,
                   let uiImage = UIImage(data: thumbData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: 150, maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if let urlStr = attachment.imageURL,
                          let url = chatVM.daemonImageURL(from: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.surfaceElevated)
                                .frame(width: 150, height: 150)
                                .overlay { ProgressView().tint(.dusk) }
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: 150, maxHeight: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        case .failure:
                            RoundedRectangle(cornerRadius: 16)
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

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private func formattedTimestamp(_ date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }
}
