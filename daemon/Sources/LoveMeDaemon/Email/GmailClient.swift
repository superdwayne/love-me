import Foundation

// MARK: - Gmail API Error

enum GmailAPIError: Error, LocalizedError, Sendable {
    case notConfigured
    case tokenRefreshFailed(String)
    case httpError(statusCode: Int, body: String)
    case invalidResponse
    case missingMessageData
    case mimeEncodingFailed
    case base64DecodingFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Gmail is not configured — no email config found"
        case .tokenRefreshFailed(let reason):
            return "Failed to refresh access token: \(reason)"
        case .httpError(let statusCode, let body):
            return "Gmail API HTTP \(statusCode): \(body)"
        case .invalidResponse:
            return "Invalid response from Gmail API"
        case .missingMessageData:
            return "Message data missing from Gmail API response"
        case .mimeEncodingFailed:
            return "Failed to encode MIME message"
        case .base64DecodingFailed:
            return "Failed to decode base64url data from Gmail API"
        }
    }
}

// MARK: - Gmail Client

actor GmailClient {
    private let configStore: EmailConfigStore
    private let session: URLSession
    private let baseURL = "https://www.googleapis.com/gmail/v1/users/me"
    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    init(configStore: EmailConfigStore) {
        self.configStore = configStore
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Public API

    /// List messages matching a Gmail search query.
    func listMessages(
        query: String,
        maxResults: Int = 20,
        pageToken: String? = nil
    ) async throws -> (messages: [GmailMessageSummary], nextPageToken: String?) {
        let accessToken = try await validAccessToken()

        var urlComponents = URLComponents(string: "\(baseURL)/messages")!
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw GmailAPIError.invalidResponse
        }

        let data = try await authorizedGET(url: url, accessToken: accessToken)

        // Decode response
        struct ListResponse: Codable {
            let messages: [MessageRef]?
            let nextPageToken: String?
            let resultSizeEstimate: Int?
        }
        struct MessageRef: Codable {
            let id: String
            let threadId: String
        }

        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        let summaries = (decoded.messages ?? []).map {
            GmailMessageSummary(id: $0.id, threadId: $0.threadId)
        }

        Logger.info("Gmail listMessages: \(summaries.count) result(s) for query '\(query)'")
        return (messages: summaries, nextPageToken: decoded.nextPageToken)
    }

    /// Fetch a full message by ID, parsing headers and body parts.
    func getMessage(id: String) async throws -> EmailMessage {
        let accessToken = try await validAccessToken()

        var urlComponents = URLComponents(string: "\(baseURL)/messages/\(id)")!
        urlComponents.queryItems = [URLQueryItem(name: "format", value: "full")]

        guard let url = urlComponents.url else {
            throw GmailAPIError.invalidResponse
        }

        let data = try await authorizedGET(url: url, accessToken: accessToken)
        let rawMessage = try JSONDecoder().decode(GmailRawMessage.self, from: data)

        return try parseRawMessage(rawMessage)
    }

    /// Download an attachment's raw data.
    func getAttachment(messageId: String, attachmentId: String) async throws -> Data {
        let accessToken = try await validAccessToken()

        let urlString = "\(baseURL)/messages/\(messageId)/attachments/\(attachmentId)"
        guard let url = URL(string: urlString) else {
            throw GmailAPIError.invalidResponse
        }

        let data = try await authorizedGET(url: url, accessToken: accessToken)

        struct AttachmentResponse: Codable {
            let size: Int
            let data: String
        }

        let decoded = try JSONDecoder().decode(AttachmentResponse.self, from: data)
        guard let attachmentData = base64URLDecode(decoded.data) else {
            throw GmailAPIError.base64DecodingFailed
        }

        Logger.info("Gmail getAttachment: \(attachmentData.count) bytes for message \(messageId)")
        return attachmentData
    }

    /// Send a new email. Returns the sent message ID.
    func sendEmail(
        to: [String],
        subject: String,
        body: String,
        cc: [String]? = nil,
        bcc: [String]? = nil,
        isHtml: Bool = false
    ) async throws -> String {
        let config = try await requireConfig()
        let accessToken = try await validAccessToken()

        let mimeMessage = buildMIMEMessage(
            from: config.emailAddress,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            body: body,
            isHtml: isHtml
        )

        guard let mimeData = mimeMessage.data(using: .utf8) else {
            throw GmailAPIError.mimeEncodingFailed
        }

        let encoded = base64URLEncode(mimeData)
        let messageId = try await sendRawMessage(raw: encoded, accessToken: accessToken)

        Logger.info("Gmail sendEmail: sent message \(messageId) to \(to.joined(separator: ", "))")
        return messageId
    }

    /// Reply to an existing email in the same thread. Returns the sent message ID.
    func replyToEmail(
        messageId: String,
        threadId: String,
        body: String
    ) async throws -> String {
        let config = try await requireConfig()
        let accessToken = try await validAccessToken()

        // Fetch the original message to get headers for reply
        let originalMessage = try await getMessage(id: messageId)

        // Build reply headers
        let replyTo = originalMessage.from
        let replySubject = originalMessage.subject.hasPrefix("Re: ")
            ? originalMessage.subject
            : "Re: \(originalMessage.subject)"

        // Build MIME message with In-Reply-To and References headers
        let messageIdHeader = "<\(messageId)@mail.gmail.com>"
        var mimeLines: [String] = []
        mimeLines.append("From: \(config.emailAddress)")
        mimeLines.append("To: \(replyTo)")
        mimeLines.append("Subject: \(replySubject)")
        mimeLines.append("In-Reply-To: \(messageIdHeader)")
        mimeLines.append("References: \(messageIdHeader)")
        mimeLines.append("MIME-Version: 1.0")
        mimeLines.append("Content-Type: text/plain; charset=\"UTF-8\"")
        mimeLines.append("Content-Transfer-Encoding: 7bit")
        mimeLines.append("")
        mimeLines.append(body)

        let mimeMessage = mimeLines.joined(separator: "\r\n")
        guard let mimeData = mimeMessage.data(using: .utf8) else {
            throw GmailAPIError.mimeEncodingFailed
        }

        let encoded = base64URLEncode(mimeData)
        let sentId = try await sendRawMessage(
            raw: encoded,
            threadId: threadId,
            accessToken: accessToken
        )

        Logger.info("Gmail replyToEmail: sent reply \(sentId) in thread \(threadId)")
        return sentId
    }

    // MARK: - Token Management

    /// Returns a valid (non-expired) access token, refreshing if needed.
    private func validAccessToken() async throws -> String {
        let config = try await requireConfig()

        if config.isTokenExpired {
            Logger.info("Gmail access token expired, refreshing...")
            return try await refreshAccessToken()
        }

        return config.accessToken
    }

    /// Refresh the access token using the stored refresh token.
    private func refreshAccessToken() async throws -> String {
        let config = try await requireConfig()

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "refresh_token": config.refreshToken,
            "grant_type": "refresh_token"
        ]
        request.httpBody = formEncode(bodyParams).data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.tokenRefreshFailed("Invalid HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GmailAPIError.tokenRefreshFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        struct TokenResponse: Codable {
            let access_token: String
            let expires_in: Int
            let token_type: String
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        let newExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))

        try await configStore.updateTokens(
            accessToken: tokenResponse.access_token,
            tokenExpiry: newExpiry
        )

        Logger.info("Gmail access token refreshed, expires in \(tokenResponse.expires_in)s")
        return tokenResponse.access_token
    }

    // MARK: - HTTP Helpers

    /// Perform an authorized GET request and return response data.
    private func authorizedGET(url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GmailAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return data
    }

    /// Send a base64url-encoded raw MIME message via the Gmail send endpoint.
    private func sendRawMessage(
        raw: String,
        threadId: String? = nil,
        accessToken: String
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/messages/send") else {
            throw GmailAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: String] = ["raw": raw]
        if let threadId {
            payload["threadId"] = threadId
        }

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GmailAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        struct SendResponse: Codable {
            let id: String
            let threadId: String
            let labelIds: [String]?
        }

        let decoded = try JSONDecoder().decode(SendResponse.self, from: data)
        return decoded.id
    }

    // MARK: - MIME Helpers

    /// Build an RFC 2822 compliant MIME message.
    private func buildMIMEMessage(
        from: String,
        to: [String],
        cc: [String]?,
        bcc: [String]?,
        subject: String,
        body: String,
        isHtml: Bool
    ) -> String {
        let contentType = isHtml
            ? "text/html; charset=\"UTF-8\""
            : "text/plain; charset=\"UTF-8\""

        var lines: [String] = []
        lines.append("From: \(from)")
        lines.append("To: \(to.joined(separator: ", "))")

        if let cc, !cc.isEmpty {
            lines.append("Cc: \(cc.joined(separator: ", "))")
        }
        if let bcc, !bcc.isEmpty {
            lines.append("Bcc: \(bcc.joined(separator: ", "))")
        }

        lines.append("Subject: \(subject)")
        lines.append("MIME-Version: 1.0")
        lines.append("Content-Type: \(contentType)")
        lines.append("Content-Transfer-Encoding: 7bit")
        lines.append("") // blank line separates headers from body
        lines.append(body)

        return lines.joined(separator: "\r\n")
    }

    // MARK: - Message Parsing

    /// Parse a Gmail API raw message response into our EmailMessage model.
    private func parseRawMessage(_ raw: GmailRawMessage) throws -> EmailMessage {
        let headers = raw.payload.headers ?? []

        func header(_ name: String) -> String {
            headers.first(where: { $0.name.lowercased() == name.lowercased() })?.value ?? ""
        }

        let from = header("From")
        let toRaw = header("To")
        let ccRaw = header("Cc")
        let subject = header("Subject")
        let dateRaw = header("Date")

        // Parse To and Cc into arrays
        let to = parseAddressList(toRaw)
        let cc = parseAddressList(ccRaw)

        // Extract body parts recursively
        var bodyText = ""
        var bodyHtml: String?
        var attachments: [EmailAttachment] = []
        extractParts(from: raw.payload, bodyText: &bodyText, bodyHtml: &bodyHtml, attachments: &attachments)

        // Parse the date
        let receivedAt = parseRFC2822Date(dateRaw) ?? Date()

        // Labels
        let labels = raw.labelIds ?? []

        return EmailMessage(
            id: raw.id,
            threadId: raw.threadId,
            from: from,
            to: to,
            cc: cc,
            subject: subject,
            bodyText: bodyText,
            bodyHtml: bodyHtml,
            attachments: attachments,
            receivedAt: receivedAt,
            labels: labels
        )
    }

    /// Recursively extract text/plain, text/html parts and attachment metadata from MIME parts.
    private func extractParts(
        from part: GmailMessagePart,
        bodyText: inout String,
        bodyHtml: inout String?,
        attachments: inout [EmailAttachment]
    ) {
        let mimeType = part.mimeType ?? ""

        // If this part has a filename, treat it as an attachment
        if let filename = part.filename, !filename.isEmpty, let body = part.body {
            let attachment = EmailAttachment(
                id: body.attachmentId ?? "",
                filename: filename,
                mimeType: mimeType,
                size: body.size ?? 0
            )
            attachments.append(attachment)
            return
        }

        // Inline body data
        if mimeType == "text/plain", let body = part.body, let data = body.data {
            if let decoded = base64URLDecode(data) {
                bodyText = String(data: decoded, encoding: .utf8) ?? bodyText
            }
        } else if mimeType == "text/html", let body = part.body, let data = body.data {
            if let decoded = base64URLDecode(data) {
                bodyHtml = String(data: decoded, encoding: .utf8)
            }
        }

        // Recurse into child parts (multipart/* containers)
        if let parts = part.parts {
            for child in parts {
                extractParts(from: child, bodyText: &bodyText, bodyHtml: &bodyHtml, attachments: &attachments)
            }
        }
    }

    // MARK: - Utility

    /// Load configuration or throw.
    private func requireConfig() async throws -> EmailConfig {
        guard let config = await configStore.load() else {
            throw GmailAPIError.notConfigured
        }
        return config
    }

    /// Parse a comma-separated email address list.
    private func parseAddressList(_ raw: String) -> [String] {
        guard !raw.isEmpty else { return [] }
        return raw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Parse an RFC 2822 date string.
    private func parseRFC2822Date(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Try common formats
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss ZZZZZ",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z"
        ]
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    /// Base64url-encode data (RFC 4648 section 5, no padding).
    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Base64url-decode a string (RFC 4648 section 5).
    private func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    /// URL-encode a dictionary as application/x-www-form-urlencoded.
    private func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }
}

// MARK: - Gmail API Response Types (private)

private struct GmailRawMessage: Codable {
    let id: String
    let threadId: String
    let labelIds: [String]?
    let payload: GmailMessagePart
}

private struct GmailMessagePart: Codable {
    let partId: String?
    let mimeType: String?
    let filename: String?
    let headers: [GmailHeader]?
    let body: GmailPartBody?
    let parts: [GmailMessagePart]?
}

private struct GmailHeader: Codable {
    let name: String
    let value: String
}

private struct GmailPartBody: Codable {
    let attachmentId: String?
    let size: Int?
    let data: String?
}
