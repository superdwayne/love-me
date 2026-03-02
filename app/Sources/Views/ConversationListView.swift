import SwiftUI

struct ConversationListView: View {
    @Environment(ConversationListViewModel.self) private var conversationListVM
    @Environment(ChatViewModel.self) private var chatVM
    @Binding var selection: String?
    @State private var showDeleteAlert = false
    @State private var conversationToDelete: String?

    var body: some View {
        List(selection: $selection) {
            if conversationListVM.isLoading {
                ForEach(0..<5, id: \.self) { _ in
                    skeletonRow
                }
                .listRowBackground(Color.surface)
            } else if conversationListVM.conversations.isEmpty {
                VStack(spacing: SolaceTheme.md) {
                    Spacer().frame(height: 60)

                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 36))
                        .foregroundStyle(.trust.opacity(0.4))

                    Text("No conversations yet")
                        .font(.displaySubtitle)
                        .foregroundStyle(.textPrimary)

                    Text("Start chatting with your AI agent.")
                        .font(.chatMessage)
                        .foregroundStyle(.trust)

                    Button {
                        chatVM.newConversation()
                        selection = chatVM.currentConversationId
                    } label: {
                        HStack(spacing: SolaceTheme.sm) {
                            Image(systemName: "plus")
                            Text("New Conversation")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, SolaceTheme.xl)
                        .padding(.vertical, SolaceTheme.md)
                        .background(Color.heart)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, SolaceTheme.xs)

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.appBackground)
                .listRowSeparator(.hidden)
            } else {
                ForEach(conversationListVM.conversations) { conversation in
                    conversationRow(conversation)
                        .tag(conversation.id)
                        .listRowBackground(
                            chatVM.currentConversationId == conversation.id
                                ? Color.surfaceElevated
                                : Color.surface
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                conversationToDelete = conversation.id
                                showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationTitle("Solace")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    chatVM.newConversation()
                    // Navigate to the chat view (nil selection = new conversation)
                    selection = chatVM.currentConversationId
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.heart)
                }
                .accessibilityLabel("New conversation")
            }
        }
        .alert("Delete Conversation", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let id = conversationToDelete {
                    conversationListVM.deleteConversation(id)
                    if chatVM.currentConversationId == id {
                        chatVM.newConversation()
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this conversation? This cannot be undone.")
        }
        .refreshable {
            conversationListVM.loadConversations()
        }
        .onAppear {
            conversationListVM.loadConversations()
        }
    }

    // MARK: - Subviews

    private func conversationRow(_ conversation: Conversation) -> some View {
        HStack(spacing: SolaceTheme.md) {
            // Active indicator
            if chatVM.currentConversationId == conversation.id {
                Rectangle()
                    .fill(Color.heart)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
            }

            VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                HStack(spacing: SolaceTheme.sm) {
                    Text(conversation.title)
                        .font(.chatMessage)
                        .fontWeight(.medium)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if conversation.sourceType == "email" {
                        Text("EMAIL")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.electricBlue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.electricBlue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                if let preview = conversation.lastMessagePreview, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 13))
                        .foregroundStyle(.trust)
                        .lineLimit(1)
                }

                Text(conversation.relativeTimestamp)
                    .font(.timestamp)
                    .foregroundStyle(.trust.opacity(0.7))
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(conversation.title), \(conversation.relativeTimestamp)")
    }

    private var skeletonRow: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.surfaceElevated)
                .frame(width: 180, height: 16)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.surfaceElevated.opacity(0.6))
                .frame(width: 80, height: 12)
        }
        .padding(.vertical, SolaceTheme.xs)
        .redacted(reason: .placeholder)
    }
}
