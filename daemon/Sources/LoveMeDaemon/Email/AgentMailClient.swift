import Foundation

/// REST API client for AgentMail (https://api.agentmail.to/v0).
/// Uses simple API key auth against the AgentMail REST API.
actor AgentMailClient {
    private let apiKey: String
    private let inboxId: String
    private let baseURL = "https://api.agentmail.to/v0"
    private let session: URLSession

    init(apiKey: String, inboxId: String) {
        self.apiKey = apiKey
        self.inboxId = inboxId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? inboxId
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Messages

    /// List messages in the inbox, optionally filtering by date.
    /// Returns full message objects in a single call.
    func listMessages(after: Date? = nil, limit: Int = 20) async throws -> [EmailMessage] {
        var urlString = "\(baseURL)/inboxes/\(inboxId)/messages?limit=\(limit)"
        if let after = after {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let isoDate = formatter.string(from: after)
            urlString += "&after=\(isoDate)"
        }
        urlString += "&order=desc"

        let data = try await request(url: urlString)
        let response = try JSONDecoder.agentMail.decode(AgentMailListResponse.self, from: data)

        return response.messages.map { $0.toEmailMessage() }
    }

    /// Get a single message by ID.
    func getMessage(id: String) async throws -> EmailMessage {
        let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let data = try await request(url: "\(baseURL)/inboxes/\(inboxId)/messages/\(encodedId)")
        let message = try JSONDecoder.agentMail.decode(AgentMailMessage.self, from: data)
        return message.toEmailMessage()
    }

    /// Send a new email.
    func sendEmail(to: [String], subject: String, body: String, cc: [String]? = nil, bcc: [String]? = nil) async throws -> String {
        let payload = AgentMailSendRequest(
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            body: body
        )

        let jsonData = try JSONEncoder().encode(payload)
        let data = try await request(url: "\(baseURL)/inboxes/\(inboxId)/messages", method: "POST", body: jsonData)

        let response = try JSONDecoder.agentMail.decode(AgentMailSendResponse.self, from: data)
        return response.message_id
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
        return response.message_id
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

/// Maps to the actual AgentMail API response shape.
/// List responses include `preview` but not `text`/`html`.
/// Detail responses include `text`, `html`, `extracted_text`.
private struct AgentMailMessage: Codable {
    let message_id: String
    let thread_id: String?
    let from: String?           // "Name <email>" or just "email"
    let to: [String]?           // ["email@example.com"]
    let cc: [String]?
    let subject: String?
    let preview: String?        // List endpoint only
    let text: String?           // Detail endpoint only
    let html: String?           // Detail endpoint only
    let timestamp: String?      // When the email was sent
    let created_at: String?     // When AgentMail received it
    let labels: [String]?
    let size: Int?

    func toEmailMessage() -> EmailMessage {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let dateStr = timestamp ?? created_at
        let receivedAt: Date
        if let dateStr = dateStr, let date = dateFormatter.date(from: dateStr) {
            receivedAt = date
        } else if let dateStr = dateStr {
            let fallback = ISO8601DateFormatter()
            receivedAt = fallback.date(from: dateStr) ?? Date()
        } else {
            receivedAt = Date()
        }

        return EmailMessage(
            id: message_id,
            threadId: thread_id ?? message_id,
            from: from ?? "",
            to: to ?? [],
            cc: cc ?? [],
            subject: subject ?? "(no subject)",
            bodyText: text ?? preview ?? "",
            bodyHtml: html,
            attachments: [],
            receivedAt: receivedAt,
            labels: labels ?? []
        )
    }

    /// Extract email from "Name <email>" format, or return as-is if plain email.
    private static func parseEmail(_ value: String) -> String {
        if let start = value.lastIndex(of: "<"),
           let end = value.lastIndex(of: ">") {
            return String(value[value.index(after: start)..<end])
        }
        return value
    }
}

private struct AgentMailSendRequest: Codable {
    let to: [String]
    let cc: [String]?
    let bcc: [String]?
    let subject: String
    let body: String
}

private struct AgentMailReplyRequest: Codable {
    let body: String
    let in_reply_to: String
}

private struct AgentMailSendResponse: Codable {
    let message_id: String
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
