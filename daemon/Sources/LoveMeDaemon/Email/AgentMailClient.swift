import Foundation

/// REST API client for AgentMail (https://api.agentmail.to/v0).
/// Replaces GmailClient + GmailAuthService with simple API key auth.
actor AgentMailClient {
    private let apiKey: String
    private let inboxId: String
    private let baseURL = "https://api.agentmail.to/v0"
    private let session: URLSession

    init(apiKey: String, inboxId: String) {
        self.apiKey = apiKey
        self.inboxId = inboxId
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Messages

    /// List messages in the inbox, optionally filtering by date.
    /// Returns full message objects (no two-step fetch like Gmail).
    func listMessages(after: Date? = nil, limit: Int = 20) async throws -> [EmailMessage] {
        var urlString = "\(baseURL)/inboxes/\(inboxId)/messages?limit=\(limit)"
        if let after = after {
            let epoch = Int(after.timeIntervalSince1970)
            urlString += "&after=\(epoch)"
        }
        urlString += "&order=desc"

        let data = try await request(url: urlString)
        let response = try JSONDecoder.agentMail.decode(AgentMailListResponse.self, from: data)

        return response.messages.map { $0.toEmailMessage() }
    }

    /// Get a single message by ID.
    func getMessage(id: String) async throws -> EmailMessage {
        let data = try await request(url: "\(baseURL)/inboxes/\(inboxId)/messages/\(id)")
        let message = try JSONDecoder.agentMail.decode(AgentMailMessage.self, from: data)
        return message.toEmailMessage()
    }

    /// Send a new email.
    func sendEmail(to: [String], subject: String, body: String, cc: [String]? = nil, bcc: [String]? = nil) async throws -> String {
        let payload = AgentMailSendRequest(
            to: to.map { AgentMailAddress(email: $0) },
            cc: cc?.map { AgentMailAddress(email: $0) },
            bcc: bcc?.map { AgentMailAddress(email: $0) },
            subject: subject,
            body: body
        )

        let jsonData = try JSONEncoder().encode(payload)
        let data = try await request(url: "\(baseURL)/inboxes/\(inboxId)/messages", method: "POST", body: jsonData)

        let response = try JSONDecoder.agentMail.decode(AgentMailSendResponse.self, from: data)
        return response.id
    }

    /// Reply to an existing message in a thread.
    func replyToEmail(messageId: String, threadId: String, body: String) async throws -> String {
        let payload = AgentMailReplyRequest(
            body: body,
            in_reply_to: messageId
        )

        let jsonData = try JSONEncoder().encode(payload)
        let data = try await request(url: "\(baseURL)/inboxes/\(inboxId)/threads/\(threadId)/messages", method: "POST", body: jsonData)

        let response = try JSONDecoder.agentMail.decode(AgentMailSendResponse.self, from: data)
        return response.id
    }

    /// Download an attachment by message and attachment ID.
    func getAttachment(messageId: String, attachmentId: String) async throws -> Data {
        try await request(url: "\(baseURL)/inboxes/\(inboxId)/messages/\(messageId)/attachments/\(attachmentId)")
    }

    // MARK: - Networking

    private func request(url urlString: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw AgentMailError.invalidURL(urlString)
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            req.httpBody = body
        }

        let (data, response) = try await session.data(for: req)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentMailError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AgentMailError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return data
    }
}

// MARK: - API Models

private struct AgentMailListResponse: Codable {
    let messages: [AgentMailMessage]
}

private struct AgentMailMessage: Codable {
    let id: String
    let thread_id: String?
    let from: AgentMailAddress?
    let to: [AgentMailAddress]?
    let cc: [AgentMailAddress]?
    let subject: String?
    let body: String?
    let html_body: String?
    let attachments: [AgentMailAttachment]?
    let created_at: String?
    let labels: [String]?

    func toEmailMessage() -> EmailMessage {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let receivedAt: Date
        if let dateStr = created_at, let date = dateFormatter.date(from: dateStr) {
            receivedAt = date
        } else if let dateStr = created_at {
            // Try without fractional seconds
            let fallback = ISO8601DateFormatter()
            receivedAt = fallback.date(from: dateStr) ?? Date()
        } else {
            receivedAt = Date()
        }

        return EmailMessage(
            id: id,
            threadId: thread_id ?? id,
            from: from?.email ?? "",
            to: (to ?? []).map(\.email),
            cc: (cc ?? []).map(\.email),
            subject: subject ?? "(no subject)",
            bodyText: body ?? "",
            bodyHtml: html_body,
            attachments: (attachments ?? []).map { $0.toEmailAttachment() },
            receivedAt: receivedAt,
            labels: labels ?? []
        )
    }
}

private struct AgentMailAddress: Codable {
    let email: String
    var name: String?
}

private struct AgentMailAttachment: Codable {
    let id: String?
    let filename: String?
    let content_type: String?
    let size: Int?

    func toEmailAttachment() -> EmailAttachment {
        EmailAttachment(
            id: id ?? "",
            filename: filename ?? "unknown",
            mimeType: content_type ?? "application/octet-stream",
            size: size ?? 0
        )
    }
}

private struct AgentMailSendRequest: Codable {
    let to: [AgentMailAddress]
    let cc: [AgentMailAddress]?
    let bcc: [AgentMailAddress]?
    let subject: String
    let body: String
}

private struct AgentMailReplyRequest: Codable {
    let body: String
    let in_reply_to: String
}

private struct AgentMailSendResponse: Codable {
    let id: String
}

// MARK: - Errors

enum AgentMailError: Error, LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "Invalid response from AgentMail API"
        case .httpError(let statusCode, let body):
            return "AgentMail API error (\(statusCode)): \(body)"
        }
    }
}

// MARK: - JSONDecoder Extension

private extension JSONDecoder {
    static let agentMail: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
}
