import Foundation
import Observation

/// Inbox message model for displaying in Agent Mail tab.
struct InboxMessage: Identifiable, Sendable {
    let id: String
    let from: String
    let subject: String
    let date: Date
    let preview: String
    let attachmentCount: Int
}

/// Display model for email trigger rules.
struct TriggerRuleDisplay: Identifiable {
    let id: String
    var workflowId: String
    var workflowName: String
    var fromContains: String
    var subjectContains: String
    var bodyContains: String
    var hasAttachment: Bool
    var enabled: Bool

    var conditionsSummary: String {
        var parts: [String] = []
        if !fromContains.isEmpty { parts.append("From: \(fromContains)") }
        if !subjectContains.isEmpty { parts.append("Subject: \(subjectContains)") }
        if !bodyContains.isEmpty { parts.append("Body: \(bodyContains)") }
        if hasAttachment { parts.append("Has attachment") }
        return parts.isEmpty ? "No conditions" : parts.joined(separator: " · ")
    }

    static func empty() -> TriggerRuleDisplay {
        TriggerRuleDisplay(
            id: UUID().uuidString,
            workflowId: "",
            workflowName: "",
            fromContains: "",
            subjectContains: "",
            bodyContains: "",
            hasAttachment: false,
            enabled: true
        )
    }
}

@Observable
@MainActor
final class EmailViewModel {
    var isEmailConnected = false
    var connectedEmail = ""
    var inboxId = ""
    var lastPollTime: String?
    var emailsProcessed = 0
    var pollingInterval = 60
    var isConnecting = false
    var authError: String?
    var inboxMessages: [InboxMessage] = []
    var triggerRules: [TriggerRuleDisplay] = []
    var isLoadingTriggers = false

    private let webSocket: WebSocketClient

    init(webSocket: WebSocketClient) {
        self.webSocket = webSocket
    }

    // MARK: - Message Handling

    func handleMessage(_ msg: WSMessage) {
        switch msg.type {
        case WSMessageType.emailStatusResult:
            handleEmailStatus(msg)

        case WSMessageType.emailConnected:
            handleConnected(msg)

        case WSMessageType.emailAuthDisconnected:
            isEmailConnected = false
            connectedEmail = ""
            inboxId = ""
            lastPollTime = nil
            emailsProcessed = 0
            inboxMessages = []

        case WSMessageType.emailMessagesListResult:
            handleMessagesListResult(msg)

        case WSMessageType.emailBriefWorkflowCreated:
            // Refresh messages list when a workflow is created from a brief
            requestInboxMessages()
            HapticManager.connectionEstablished()

        case WSMessageType.emailTriggersListResult:
            handleTriggersListResult(msg)

        case WSMessageType.emailTriggerCreated:
            handleTriggerCreated(msg)

        case WSMessageType.emailTriggerUpdated:
            handleTriggerUpdated(msg)

        case WSMessageType.emailTriggerDeleted:
            handleTriggerDeleted(msg)

        case WSMessageType.error:
            if let code = msg.metadata?["code"]?.stringValue,
               code.contains("API_KEY") || code.contains("AUTH") || code.contains("EMAIL") || code.contains("CONFIG") {
                isConnecting = false
                authError = msg.content
                HapticManager.toolError()
            }

        default:
            break
        }
    }

    // MARK: - Actions

    func requestEmailStatus() {
        webSocket.send(WSMessage(type: WSMessageType.emailStatus))
    }

    func connectAgentMail(apiKey: String, inboxId: String) {
        isConnecting = true
        authError = nil
        HapticManager.messageSent()
        webSocket.send(WSMessage(
            type: WSMessageType.emailConnect,
            metadata: [
                "apiKey": .string(apiKey),
                "inboxId": .string(inboxId)
            ]
        ))
    }

    func disconnectEmail() {
        HapticManager.connectionLost()
        webSocket.send(WSMessage(type: WSMessageType.emailAuthDisconnect))
        isEmailConnected = false
        connectedEmail = ""
        inboxId = ""
        lastPollTime = nil
        emailsProcessed = 0
        inboxMessages = []
    }

    func requestInboxMessages() {
        webSocket.send(WSMessage(type: WSMessageType.emailMessagesList))
    }

    func updatePollingInterval(_ seconds: Int) {
        pollingInterval = seconds
        webSocket.send(WSMessage(
            type: WSMessageType.emailUpdatePolling,
            metadata: ["intervalSeconds": .int(seconds)]
        ))
    }

    // MARK: - Trigger Actions

    func loadTriggerRules() {
        isLoadingTriggers = true
        webSocket.send(WSMessage(type: WSMessageType.emailTriggersList))
    }

    func createTriggerRule(_ rule: TriggerRuleDisplay) {
        webSocket.send(WSMessage(
            type: WSMessageType.emailTriggerCreate,
            metadata: encodeTriggerRule(rule)
        ))
        triggerRules.append(rule)
        HapticManager.toolCompleted()
    }

    func updateTriggerRule(_ rule: TriggerRuleDisplay) {
        webSocket.send(WSMessage(
            type: WSMessageType.emailTriggerUpdate,
            metadata: encodeTriggerRule(rule)
        ))
        if let index = triggerRules.firstIndex(where: { $0.id == rule.id }) {
            triggerRules[index] = rule
        }
        HapticManager.toolCompleted()
    }

    func deleteTriggerRule(_ rule: TriggerRuleDisplay) {
        webSocket.send(WSMessage(
            type: WSMessageType.emailTriggerDelete,
            id: rule.id
        ))
        triggerRules.removeAll { $0.id == rule.id }
        HapticManager.toolError()
    }

    func toggleTriggerRule(_ rule: TriggerRuleDisplay, enabled: Bool) {
        var updated = rule
        updated.enabled = enabled
        updateTriggerRule(updated)
    }

    // MARK: - Private Handlers

    private func handleEmailStatus(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }

        if let configured = meta["configured"]?.boolValue {
            isEmailConnected = configured
        }
        if let email = meta["emailAddress"]?.stringValue {
            connectedEmail = email
        }
        if let inbox = meta["inboxId"]?.stringValue {
            inboxId = inbox
        }
        if let lastPoll = meta["lastPollTime"]?.stringValue {
            lastPollTime = lastPoll
        }
        if let processed = meta["totalProcessed"]?.intValue {
            emailsProcessed = processed
        }
        if let interval = meta["pollingIntervalSeconds"]?.intValue {
            pollingInterval = interval
        }

        if isConnecting && isEmailConnected {
            isConnecting = false
            HapticManager.connectionEstablished()
        }

        // Auto-load inbox messages when connected
        if isEmailConnected {
            requestInboxMessages()
        }
    }

    private func handleConnected(_ msg: WSMessage) {
        isConnecting = false
        if let email = msg.metadata?["emailAddress"]?.stringValue {
            connectedEmail = email
        }
        if let inbox = msg.metadata?["inboxId"]?.stringValue {
            inboxId = inbox
        }
        isEmailConnected = true
        HapticManager.connectionEstablished()

        // Load inbox messages
        requestInboxMessages()
    }

    private func handleMessagesListResult(_ msg: WSMessage) {
        guard case .array(let items) = msg.metadata?["messages"] else { return }

        let dateFormatter = ISO8601DateFormatter()
        var loaded: [InboxMessage] = []

        for item in items {
            guard case .object(let dict) = item else { continue }
            guard let id = dict["id"]?.stringValue else { continue }

            let date: Date
            if let dateStr = dict["date"]?.stringValue,
               let parsed = dateFormatter.date(from: dateStr) {
                date = parsed
            } else {
                date = Date()
            }

            loaded.append(InboxMessage(
                id: id,
                from: dict["from"]?.stringValue ?? "",
                subject: dict["subject"]?.stringValue ?? "(no subject)",
                date: date,
                preview: dict["preview"]?.stringValue ?? "",
                attachmentCount: dict["attachmentCount"]?.intValue ?? 0
            ))
        }

        inboxMessages = loaded
    }

    private func handleTriggersListResult(_ msg: WSMessage) {
        isLoadingTriggers = false
        guard case .array(let items) = msg.metadata?["rules"] else { return }

        var loaded: [TriggerRuleDisplay] = []
        for item in items {
            guard case .object(let dict) = item else { continue }
            guard let id = dict["id"]?.stringValue else { continue }

            loaded.append(TriggerRuleDisplay(
                id: id,
                workflowId: dict["workflowId"]?.stringValue ?? "",
                workflowName: dict["workflowName"]?.stringValue ?? "",
                fromContains: dict["fromContains"]?.stringValue ?? "",
                subjectContains: dict["subjectContains"]?.stringValue ?? "",
                bodyContains: dict["bodyContains"]?.stringValue ?? "",
                hasAttachment: dict["hasAttachment"]?.boolValue ?? false,
                enabled: dict["enabled"]?.boolValue ?? true
            ))
        }

        triggerRules = loaded
    }

    private func handleTriggerCreated(_ msg: WSMessage) {
        guard let meta = msg.metadata,
              let id = meta["id"]?.stringValue else { return }
        // Update optimistic entry with server-confirmed data
        if let index = triggerRules.firstIndex(where: { $0.id == id }) {
            triggerRules[index].workflowName = meta["workflowName"]?.stringValue ?? triggerRules[index].workflowName
        }
    }

    private func handleTriggerUpdated(_ msg: WSMessage) {
        guard let meta = msg.metadata,
              let id = meta["id"]?.stringValue else { return }
        if let index = triggerRules.firstIndex(where: { $0.id == id }) {
            triggerRules[index].enabled = meta["enabled"]?.boolValue ?? triggerRules[index].enabled
            triggerRules[index].workflowName = meta["workflowName"]?.stringValue ?? triggerRules[index].workflowName
        }
    }

    private func handleTriggerDeleted(_ msg: WSMessage) {
        guard let id = msg.metadata?["id"]?.stringValue ?? msg.id else { return }
        triggerRules.removeAll { $0.id == id }
    }

    private func encodeTriggerRule(_ rule: TriggerRuleDisplay) -> [String: MetadataValue] {
        [
            "id": .string(rule.id),
            "workflowId": .string(rule.workflowId),
            "fromContains": .string(rule.fromContains),
            "subjectContains": .string(rule.subjectContains),
            "bodyContains": .string(rule.bodyContains),
            "hasAttachment": .bool(rule.hasAttachment),
            "enabled": .bool(rule.enabled),
        ]
    }
}
