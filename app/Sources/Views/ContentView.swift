import SwiftUI

struct ContentView: View {
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(ConversationListViewModel.self) private var conversationListVM
    @Environment(WorkflowViewModel.self) private var workflowVM
    @State private var selectedConversation: String?
    @State private var selectedTab: AppTab = .chat

    enum AppTab: String {
        case chat
        case workflows
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
        }
        .tint(.heart)
    }
}
