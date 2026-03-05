import SwiftUI
import UserNotifications

@main @MainActor
struct SolaceApp: App {
    @State private var webSocket: WebSocketClient
    @State private var chatVM: ChatViewModel
    @State private var conversationListVM: ConversationListViewModel
    @State private var workflowVM: WorkflowViewModel
    @State private var emailVM: EmailViewModel
    @State private var settingsVM: SettingsViewModel
    @State private var ambientVM: AmbientListeningViewModel
    @State private var bonjourBrowser = BonjourBrowser()
    @State private var linkPreviewService = LinkPreviewService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let ws = WebSocketClient()
        let chat = ChatViewModel(webSocket: ws)
        let convList = ConversationListViewModel(webSocket: ws)
        let workflow = WorkflowViewModel(webSocket: ws)
        let email = EmailViewModel(webSocket: ws)
        let settings = SettingsViewModel(webSocket: ws)
        let ambient = AmbientListeningViewModel(webSocket: ws)

        // Wire up message routing to all view models
        ws.onMessage = { @MainActor message in
            chat.handleMessage(message)
            convList.handleMessage(message)
            workflow.handleMessage(message)
            email.handleMessage(message)
            settings.handleMessage(message)
            ambient.handleMessage(message)
        }

        _webSocket = State(initialValue: ws)
        _chatVM = State(initialValue: chat)
        _conversationListVM = State(initialValue: convList)
        _workflowVM = State(initialValue: workflow)
        _emailVM = State(initialValue: email)
        _settingsVM = State(initialValue: settings)
        _ambientVM = State(initialValue: ambient)

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
                .environment(emailVM)
                .environment(settingsVM)
                .environment(ambientVM)
                .environment(bonjourBrowser)
                .environment(linkPreviewService)
                .preferredColorScheme(.light)
                .task {
                    await autoConnect()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    let musicEnabled = UserDefaults.standard.bool(forKey: "ambient_music_enabled")
                    switch newPhase {
                    case .active:
                        if musicEnabled {
                            AmbientMusicManager.shared.fadeIn()
                        }
                    case .background:
                        if AmbientMusicManager.shared.isPlaying {
                            AmbientMusicManager.shared.fadeOut()
                        }
                        if ambientVM.isListening {
                            ambientVM.toggleListening()
                        }
                    default:
                        break
                    }
                }
        }
    }

    private func autoConnect() async {
        let host = UserDefaults.standard.string(forKey: "ws_host") ?? "localhost"

        // If the user hasn't configured a custom host, try Bonjour discovery first
        guard host == "localhost" else {
            webSocket.connect()
            return
        }

        // Wait up to 2 seconds for Bonjour to discover a daemon
        for _ in 0..<20 {
            if let daemon = bonjourBrowser.discoveredDaemons.first {
                UserDefaults.standard.set(daemon.host, forKey: "ws_host")
                UserDefaults.standard.set(Int(daemon.port), forKey: "ws_port")
                webSocket.connect()
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Fallback: connect to localhost (works in simulator)
        webSocket.connect()
    }
}
