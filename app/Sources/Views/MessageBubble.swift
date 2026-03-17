import SwiftUI

// MARK: - Streaming Dots Animation

private struct StreamingDotsView: View {
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SolaceTheme.xs) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.textSecondary)
                    .frame(width: 6, height: 6)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

struct MessageBubble: View {
    let message: Message
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0
    @State private var didTriggerReply = false
    @State private var renderedContent: AttributedString = AttributedString()
    @State private var lastRenderTime: Date = .distantPast

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: UIScreen.main.bounds.width * (1 - SolaceTheme.bubbleMaxWidthRatio))
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: SolaceTheme.xs) {
                // Assistant attribution label
                if message.role == .assistant && !message.content.isEmpty {
                    HStack(spacing: SolaceTheme.xs) {
                        Circle()
                            .fill(Color.coral)
                            .frame(width: 6, height: 6)
                        Text("Solace")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.coral)
                    }
                }

                bubbleContent
                    .contextMenu {
                        Button {
                            chatVM.copyMessageContent(message)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        if message.role == .user && !chatVM.isStreaming {
                            Button {
                                chatVM.startEditing(message)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }

                        if message.role == .user {
                            Button {
                                chatVM.retryMessage(message)
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                        }

                        Button(role: .destructive) {
                            chatVM.deleteMessage(message)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                // Timestamp
                Text(formattedTimestamp)
                    .font(.timestamp)
                    .foregroundStyle(.textSecondary)

                // Edited indicator
                if message.isEdited {
                    Text("(edited)")
                        .font(.system(size: 10))
                        .foregroundStyle(.textSecondary.opacity(0.6))
                }

                // Failed state
                if message.sendFailed {
                    Text("Not sent. Tap to retry.")
                        .font(.system(size: 12))
                        .foregroundStyle(.softRed)
                        .onTapGesture {
                            chatVM.retryMessage(message)
                        }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: UIScreen.main.bounds.width * (1 - SolaceTheme.bubbleMaxWidthRatio))
            }
        }
        .opacity(message.sendFailed ? 0.6 : 1.0)
        .opacity(appeared ? 1.0 : 0.0)
        .offset(y: appeared ? 0 : (message.role == .user ? 10 : 0))
        .scaleEffect(appeared ? 1.0 : (message.role == .user ? 0.8 : 1.0))
        .offset(x: appeared ? 0 : (message.role == .assistant ? -20 : 0))
        .offset(x: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // Only allow right-swipe
                    guard value.translation.width > 0 else { return }
                    dragOffset = min(value.translation.width * 0.4, 60)
                    if dragOffset > 40 && !didTriggerReply {
                        didTriggerReply = true
                        HapticManager.longPress()
                    }
                }
                .onEnded { _ in
                    if didTriggerReply {
                        chatVM.quoteReply(message)
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
                withAnimation(.spring(duration: SolaceTheme.springDuration)) {
                    appeared = true
                }
            }
        }
    }

    private var audioAttachments: [MessageAttachment] {
        message.attachments.filter { $0.isAudio }
    }

    private var bubbleContent: some View {
        Group {
            if chatVM.editingMessageId == message.id {
                editingView
            } else if message.content.isEmpty && message.isStreaming && audioAttachments.isEmpty {
                if let loadingStatus = message.loadingStatus {
                    modelLoadingView(loadingStatus)
                } else {
                    streamingPlaceholder
                }
            } else {
                VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                    // Voice note players for audio attachments
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

                    // Text content (may be empty for voice-only messages)
                    if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(renderedContent)
                            .font(.chatMessage)
                            .foregroundStyle(message.role == .user ? .white : .textPrimary)
                            .onChange(of: message.content) { _, newContent in
                                throttleRender(newContent)
                            }
                            .onChange(of: message.isStreaming) { _, streaming in
                                if !streaming {
                                    renderWithSearch(message.content)
                                }
                            }
                            .onAppear {
                                renderWithSearch(message.content)
                            }
                            .onChange(of: chatVM.searchQuery) { _, _ in
                                renderWithSearch(message.content)
                            }
                            .onChange(of: chatVM.currentMatchIndex) { _, _ in
                                renderWithSearch(message.content)
                            }
                    }

                    // Link previews (assistant messages only, after streaming)
                    if message.role == .assistant && !message.isStreaming {
                        LinkPreviewContainer(
                            messageContent: message.content,
                            isStreaming: message.isStreaming
                        )
                    }
                }
            }
        }
        .padding(message.role == .user ? SolaceTheme.md : SolaceTheme.xs)
        .frame(maxWidth: UIScreen.main.bounds.width * SolaceTheme.bubbleMaxWidthRatio,
               alignment: message.role == .user ? .trailing : .leading)
        .background(bubbleBackground)
        .clipShape(bubbleShape)
    }

    private var editingView: some View {
        @Bindable var vm = chatVM
        return VStack(alignment: .trailing, spacing: SolaceTheme.sm) {
            TextField("Edit message...", text: $vm.editingText, axis: .vertical)
                .font(.chatMessage)
                .foregroundStyle(.white)
                .lineLimit(1...10)

            HStack(spacing: SolaceTheme.sm) {
                Button {
                    chatVM.cancelEditing()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, SolaceTheme.md)
                        .padding(.vertical, SolaceTheme.xs)
                }

                Button {
                    chatVM.saveEdit()
                } label: {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, SolaceTheme.md)
                        .padding(.vertical, SolaceTheme.xs)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var streamingPlaceholder: some View {
        StreamingDotsView()
            .padding(.vertical, SolaceTheme.sm)
    }

    private func modelLoadingView(_ status: String) -> some View {
        HStack(spacing: SolaceTheme.sm) {
            ProgressView()
                .tint(.textSecondary)
                .scaleEffect(0.8)
            Text(status)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.textSecondary)
        }
        .padding(.vertical, SolaceTheme.xs)
    }

    private var bubbleBackground: Color {
        message.role == .user
            ? .heart
            : .clear
    }

    private var bubbleShape: UnevenRoundedRectangle {
        if message.role == .user {
            return UnevenRoundedRectangle(
                topLeadingRadius: SolaceTheme.bubbleRadius,
                bottomLeadingRadius: SolaceTheme.bubbleRadius,
                bottomTrailingRadius: SolaceTheme.bubbleTailRadius,
                topTrailingRadius: SolaceTheme.bubbleRadius
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: SolaceTheme.bubbleRadius,
                bottomLeadingRadius: SolaceTheme.bubbleRadius,
                bottomTrailingRadius: SolaceTheme.bubbleRadius,
                topTrailingRadius: SolaceTheme.bubbleRadius
            )
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

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private var formattedTimestamp: String {
        Self.timestampFormatter.string(from: message.timestamp)
    }
}
