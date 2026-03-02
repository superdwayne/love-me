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

/// Display model for email approval items.
struct EmailApprovalDisplay: Identifiable {
    let id: String
    let classification: String
    let emailFrom: String
    let emailSubject: String
    let emailPreview: String
    var workflowId: String?
    var workflowName: String?
    var workflowStepCount: Int?
    var suggestedReply: String?
    var conversationId: String?
    var summary: String?
    var recommendation: String?
    let createdAt: Date
    var status: String

    var isPending: Bool { status == "pending" }
    var isBuilding: Bool { status == "building" }
    var isCompleted: Bool { status == "completed" }
    var isFailed: Bool { status == "failed" }

    var recommendationLabel: String? {
        switch recommendation {
        case "chat": return "Suggested: Open in Chat"
        case "workflow": return "Suggested: Auto Workflow"
        default: return nil
        }
    }

    var statusLabel: String {
        switch status {
        case "pending": return "Pending"
        case "building": return "Building workflow..."
        case "approved": return "Approved"
        case "dismissed": return "Dismissed"
        case "completed": return "Completed"
        case "failed": return "Failed"
        default: return status.capitalized
        }
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
    var pendingApprovals: [EmailApprovalDisplay] = []
    var showApprovalBanner = false
    var navigateToConversationId: String?

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
            requestInboxMessages()
            HapticManager.connectionEstablished()

        case WSMessageType.emailApprovalPending:
            handleApprovalPending(msg)

        case WSMessageType.emailApprovalUpdated:
            handleApprovalUpdated(msg)

        case WSMessageType.emailApprovalsListResult:
            handleApprovalsListResult(msg)

        case WSMessageType.emailAutoReplyStatus:
            handleAutoReplyStatus(msg)

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

    // MARK: - Approval Actions

    func requestPendingApprovals() {
        webSocket.send(WSMessage(type: WSMessageType.emailApprovalsList))
    }

    func openEmailChat(approvalId: String) {
        guard let index = pendingApprovals.firstIndex(where: { $0.id == approvalId }) else { return }
        let conversationId = pendingApprovals[index].conversationId

        webSocket.send(WSMessage(
            type: WSMessageType.emailApprovalApprove,
            id: approvalId,
            metadata: ["action": .string("chat")]
        ))

        // Optimistic update
        pendingApprovals[index].status = "approved"

        // Trigger navigation to the conversation
        if let convId = conversationId {
            navigateToConversationId = convId
        }
        HapticManager.toolCompleted()
    }

    func autoCreateWorkflow(approvalId: String) {
        webSocket.send(WSMessage(
            type: WSMessageType.emailApprovalApprove,
            id: approvalId,
            metadata: ["action": .string("auto_workflow")]
        ))
        // Optimistic update
        if let index = pendingApprovals.firstIndex(where: { $0.id == approvalId }) {
            pendingApprovals[index].status = "approved"
        }
        HapticManager.toolCompleted()
    }

    func saveAutoFlow(approvalId: String) {
        webSocket.send(WSMessage(
            type: WSMessageType.emailApprovalApprove,
            id: approvalId,
            metadata: ["action": .string("save_auto_flow")]
        ))
        // Optimistic update — show building state
        if let index = pendingApprovals.firstIndex(where: { $0.id == approvalId }) {
            pendingApprovals[index].status = "building"
        }
        HapticManager.messageSent()
    }

    func dismissEmail(approvalId: String) {
        webSocket.send(WSMessage(
            type: WSMessageType.emailApprovalDismiss,
            id: approvalId
        ))
        pendingApprovals.removeAll { $0.id == approvalId }
        HapticManager.messageSent()
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

        // Auto-load inbox messages and approvals when connected
        if isEmailConnected {
            requestInboxMessages()
            requestPendingApprovals()
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

        // Load inbox messages and pending approvals
        requestInboxMessages()
        requestPendingApprovals()
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

    // MARK: - Approval Handlers

    private func handleApprovalPending(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }
        if let display = parseApprovalFromMetadata(meta) {
            pendingApprovals.insert(display, at: 0)
            showApprovalBanner = true
            HapticManager.connectionEstablished()
        }
    }

    private func handleApprovalUpdated(_ msg: WSMessage) {
        guard let meta = msg.metadata,
              let approvalId = meta["approvalId"]?.stringValue else { return }
        if let index = pendingApprovals.firstIndex(where: { $0.id == approvalId }) {
            if let status = meta["status"]?.stringValue {
                pendingApprovals[index].status = status
            }
        }
    }

    private func handleApprovalsListResult(_ msg: WSMessage) {
        guard case .array(let items) = msg.metadata?["approvals"] else { return }

        var loaded: [EmailApprovalDisplay] = []
        for item in items {
            guard case .object(let dict) = item else { continue }
            if let display = parseApprovalFromMetadata(dict) {
                loaded.append(display)
            }
        }

        pendingApprovals = loaded
        showApprovalBanner = loaded.contains { $0.isPending }
    }

    private func handleAutoReplyStatus(_ msg: WSMessage) {
        guard let meta = msg.metadata,
              let approvalId = msg.id else { return }
        if let index = pendingApprovals.firstIndex(where: { $0.id == approvalId }) {
            if let status = meta["status"]?.stringValue {
                pendingApprovals[index].status = status
            }
        }
        switch meta["status"]?.stringValue {
        case "completed":
            HapticManager.toolCompleted()
        case "building":
            break // No haptic for in-progress building
        default:
            HapticManager.toolError()
        }
    }

    private func parseApprovalFromMetadata(_ meta: [String: MetadataValue]) -> EmailApprovalDisplay? {
        guard let approvalId = meta["approvalId"]?.stringValue else { return nil }

        let dateFormatter = ISO8601DateFormatter()
        let createdAt: Date
        if let dateStr = meta["createdAt"]?.stringValue,
           let parsed = dateFormatter.date(from: dateStr) {
            createdAt = parsed
        } else {
            createdAt = Date()
        }

        return EmailApprovalDisplay(
            id: approvalId,
            classification: meta["classification"]?.stringValue ?? "workflow",
            emailFrom: meta["emailFrom"]?.stringValue ?? "",
            emailSubject: meta["emailSubject"]?.stringValue ?? "(no subject)",
            emailPreview: meta["emailPreview"]?.stringValue ?? "",
            workflowId: meta["workflowId"]?.stringValue,
            workflowName: meta["workflowName"]?.stringValue,
            workflowStepCount: meta["workflowStepCount"]?.intValue,
            suggestedReply: meta["suggestedReply"]?.stringValue,
            conversationId: meta["conversationId"]?.stringValue,
            summary: meta["summary"]?.stringValue,
            recommendation: meta["recommendation"]?.stringValue,
            createdAt: createdAt,
            status: meta["status"]?.stringValue ?? "pending"
        )
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
