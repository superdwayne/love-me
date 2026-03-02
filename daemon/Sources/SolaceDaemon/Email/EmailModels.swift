import Foundation

// MARK: - Email Configuration

struct EmailConfig: Codable, Sendable {
    var apiKey: String
    var inboxId: String
    var emailAddress: String
    var pollingIntervalSeconds: Int

    init(
        apiKey: String,
        inboxId: String,
        emailAddress: String,
        pollingIntervalSeconds: Int = 60
    ) {
        self.apiKey = apiKey
        self.inboxId = inboxId
        self.emailAddress = emailAddress
        self.pollingIntervalSeconds = pollingIntervalSeconds
    }
}

// MARK: - Email Message

struct EmailMessage: Codable, Sendable {
    let id: String
    let threadId: String
    let from: String
    let to: [String]
    let cc: [String]
    let subject: String
    let bodyText: String
    let bodyHtml: String?
    let attachments: [EmailAttachment]
    let receivedAt: Date
    let labels: [String]
}

struct EmailAttachment: Codable, Sendable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int
}

// MARK: - Email Trigger Rule

struct EmailTriggerRule: Codable, Sendable, Identifiable {
    let id: String
    var workflowId: String
    var conditions: EmailTriggerConditions
    var enabled: Bool

    init(
        id: String = UUID().uuidString,
        workflowId: String,
        conditions: EmailTriggerConditions,
        enabled: Bool = true
    ) {
        self.id = id
        self.workflowId = workflowId
        self.conditions = conditions
        self.enabled = enabled
    }
}

struct EmailTriggerConditions: Codable, Sendable {
    var fromContains: String?
    var subjectContains: String?
    var bodyContains: String?
    var hasAttachment: Bool?
    var labelEquals: String?

    /// Returns true if the email matches all non-nil conditions.
    func matches(_ email: EmailMessage) -> Bool {
        if let from = fromContains, !from.isEmpty {
            guard email.from.localizedCaseInsensitiveContains(from) else { return false }
        }
        if let subject = subjectContains, !subject.isEmpty {
            guard email.subject.localizedCaseInsensitiveContains(subject) else { return false }
        }
        if let body = bodyContains, !body.isEmpty {
            guard email.bodyText.localizedCaseInsensitiveContains(body) else { return false }
        }
        if let hasAttach = hasAttachment, hasAttach {
            guard !email.attachments.isEmpty else { return false }
        }
        if let label = labelEquals, !label.isEmpty {
            guard email.labels.contains(label) else { return false }
        }
        return true
    }
}

// MARK: - Email Classification

enum EmailClassification: String, Codable, Sendable {
    case workflow
    case simpleReply
    case noAction
}

enum ApprovalStatus: String, Codable, Sendable {
    case pending
    case approved
    case dismissed
    case completed
    case failed
}

struct EmailMessageSummary: Codable, Sendable {
    let messageId: String
    let threadId: String
    let from: String
    let subject: String
    let preview: String
    let bodyText: String
    let receivedAt: Date

    init(from email: EmailMessage) {
        self.messageId = email.id
        self.threadId = email.threadId
        self.from = email.from
        self.subject = email.subject
        self.preview = String(email.bodyText.prefix(200))
        self.bodyText = String(email.bodyText.prefix(4000))
        self.receivedAt = email.receivedAt
    }
}

struct PendingEmailApproval: Codable, Sendable, Identifiable {
    let id: String
    let email: EmailMessageSummary
    let classification: EmailClassification
    var workflowId: String?
    var workflowName: String?
    var workflowStepCount: Int?
    var suggestedReply: String?
    var conversationId: String?
    var summary: String?
    var recommendation: String?
    let createdAt: Date
    var status: ApprovalStatus

    init(
        id: String = UUID().uuidString,
        email: EmailMessageSummary,
        classification: EmailClassification,
        workflowId: String? = nil,
        workflowName: String? = nil,
        workflowStepCount: Int? = nil,
        suggestedReply: String? = nil,
        conversationId: String? = nil,
        summary: String? = nil,
        recommendation: String? = nil,
        createdAt: Date = Date(),
        status: ApprovalStatus = .pending
    ) {
        self.id = id
        self.email = email
        self.classification = classification
        self.workflowId = workflowId
        self.workflowName = workflowName
        self.workflowStepCount = workflowStepCount
        self.suggestedReply = suggestedReply
        self.conversationId = conversationId
        self.summary = summary
        self.recommendation = recommendation
        self.createdAt = createdAt
        self.status = status
    }
}

// MARK: - Email Polling State

struct EmailPollingState: Codable, Sendable {
    var lastSeenMessageId: String?
    var lastSeenTimestamp: Date?
    var totalProcessed: Int

    init(lastSeenMessageId: String? = nil, lastSeenTimestamp: Date? = nil, totalProcessed: Int = 0) {
        self.lastSeenMessageId = lastSeenMessageId
        self.lastSeenTimestamp = lastSeenTimestamp
        self.totalProcessed = totalProcessed
    }
}
