import Foundation
import Observation

@Observable
@MainActor
final class ConversationListViewModel {
    var conversations: [Conversation] = []
    var isLoading: Bool = false

    private let webSocket: WebSocketClient

    init(webSocket: WebSocketClient) {
        self.webSocket = webSocket
    }

    func loadConversations() {
        isLoading = true
        let msg = WSMessage(type: WSMessageType.listConversations)
        webSocket.send(msg)
    }

    func deleteConversation(_ id: String) {
        let msg = WSMessage(
            type: WSMessageType.deleteConversation,
            conversationId: id
        )
        webSocket.send(msg)
        conversations.removeAll { $0.id == id }
    }

    func handleMessage(_ msg: WSMessage) {
        switch msg.type {
        case WSMessageType.status:
            // Connection established - load conversations now
            loadConversations()

        case WSMessageType.conversationList:
            handleConversationList(msg)

        case WSMessageType.conversationDeleted:
            if let convId = msg.conversationId {
                conversations.removeAll { $0.id == convId }
            }

        case WSMessageType.conversationCreated:
            if let convId = msg.conversationId {
                let title = msg.metadata?["title"]?.stringValue ?? "New Conversation"
                let conversation = Conversation(
                    id: convId,
                    title: title,
                    lastMessageAt: Date(),
                    messageCount: 0
                )
                conversations.insert(conversation, at: 0)
            }

        default:
            break
        }
    }

    // MARK: - Private

    private func handleConversationList(_ msg: WSMessage) {
        isLoading = false
        guard case .array(let items) = msg.metadata?["conversations"] else {
            isLoading = false
            return
        }

        var loaded: [Conversation] = []
        let dateFormatter = ISO8601DateFormatter()

        for item in items {
            guard case .object(let dict) = item else { continue }
            guard let id = dict["id"]?.stringValue,
                  let title = dict["title"]?.stringValue else { continue }

            let lastMessageAt: Date
            if let dateStr = dict["lastMessageAt"]?.stringValue,
               let date = dateFormatter.date(from: dateStr) {
                lastMessageAt = date
            } else {
                lastMessageAt = Date()
            }

            let messageCount = dict["messageCount"]?.intValue ?? 0

            loaded.append(Conversation(
                id: id,
                title: title,
                lastMessageAt: lastMessageAt,
                messageCount: messageCount
            ))
        }

        conversations = loaded.sorted { $0.lastMessageAt > $1.lastMessageAt }
    }
}
