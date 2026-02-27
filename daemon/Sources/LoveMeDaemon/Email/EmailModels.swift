import Foundation

// MARK: - Email Configuration

struct EmailConfig: Codable, Sendable {
    let provider: EmailProvider
    var clientId: String
    var clientSecret: String
    var refreshToken: String
    var accessToken: String
    var tokenExpiry: Date
    var emailAddress: String
    var pollingIntervalSeconds: Int

    init(
        provider: EmailProvider = .gmail,
        clientId: String,
        clientSecret: String,
        refreshToken: String,
        accessToken: String,
        tokenExpiry: Date,
        emailAddress: String,
        pollingIntervalSeconds: Int = 60
    ) {
        self.provider = provider
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.refreshToken = refreshToken
        self.accessToken = accessToken
        self.tokenExpiry = tokenExpiry
        self.emailAddress = emailAddress
        self.pollingIntervalSeconds = pollingIntervalSeconds
    }

    var isTokenExpired: Bool {
        Date() >= tokenExpiry
    }
}

enum EmailProvider: String, Codable, Sendable {
    case gmail
    case outlook
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

// MARK: - Gmail Message Summary

/// Lightweight message reference returned by Gmail list operations.
struct GmailMessageSummary: Sendable {
    let id: String
    let threadId: String
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
