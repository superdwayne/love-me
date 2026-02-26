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
                Text("No conversations yet")
                    .font(.chatMessage)
                    .foregroundStyle(.trust)
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
        .navigationTitle("love.Me")
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
        .onAppear {
            conversationListVM.loadConversations()
        }
    }

    // MARK: - Subviews

    private func conversationRow(_ conversation: Conversation) -> some View {
        HStack(spacing: LoveMeTheme.md) {
            // Active indicator
            if chatVM.currentConversationId == conversation.id {
                Rectangle()
                    .fill(Color.heart)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
            }

            VStack(alignment: .leading, spacing: LoveMeTheme.xs) {
                Text(conversation.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(conversation.relativeTimestamp)
                    .font(.system(size: 13))
                    .foregroundStyle(.trust)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(conversation.title), \(conversation.relativeTimestamp)")
    }

    private var skeletonRow: some View {
        VStack(alignment: .leading, spacing: LoveMeTheme.sm) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.surfaceElevated)
                .frame(width: 180, height: 16)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.surfaceElevated.opacity(0.6))
                .frame(width: 80, height: 12)
        }
        .padding(.vertical, LoveMeTheme.xs)
        .redacted(reason: .placeholder)
    }
}
