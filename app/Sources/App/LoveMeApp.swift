import SwiftUI
import UserNotifications

@main @MainActor
struct LoveMeApp: App {
    @State private var webSocket: WebSocketClient
    @State private var chatVM: ChatViewModel
    @State private var conversationListVM: ConversationListViewModel
    @State private var workflowVM: WorkflowViewModel

    init() {
        let ws = WebSocketClient()
        let chat = ChatViewModel(webSocket: ws)
        let convList = ConversationListViewModel(webSocket: ws)
        let workflow = WorkflowViewModel(webSocket: ws)

        // Wire up message routing to all view models
        ws.onMessage = { @MainActor message in
            chat.handleMessage(message)
            convList.handleMessage(message)
            workflow.handleMessage(message)
        }

        _webSocket = State(initialValue: ws)
        _chatVM = State(initialValue: chat)
        _conversationListVM = State(initialValue: convList)
        _workflowVM = State(initialValue: workflow)

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(webSocket)
                .environment(chatVM)
                .environment(conversationListVM)
                .environment(workflowVM)
                .preferredColorScheme(.dark)
                .onAppear {
                    webSocket.connect()
                }
        }
    }
}
