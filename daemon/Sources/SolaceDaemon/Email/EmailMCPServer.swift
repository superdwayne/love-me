import Foundation

// MARK: - Email Tool Types

/// Defines an email tool's name, description, and parameter schema for registration with MCPManager.
struct EmailToolDefinition: Sendable {
    let name: String
    let description: String
    let parameters: [EmailToolParameter]
}

/// A single parameter in an email tool definition.
struct EmailToolParameter: Sendable {
    let name: String
    let type: String
    let description: String
    let required: Bool
}

/// Result from executing an email tool.
struct EmailToolResult: Sendable {
    let content: String
    let isError: Bool

    static func success(_ content: String) -> EmailToolResult {
        EmailToolResult(content: content, isError: false)
    }

    static func error(_ message: String) -> EmailToolResult {
        EmailToolResult(content: message, isError: true)
    }
}

// MARK: - Email MCP Server Errors

enum EmailMCPError: Error, LocalizedError {
    case unknownTool(String)
    case missingParameter(String)
    case invalidParameter(String, String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown email tool: \(name)"
        case .missingParameter(let param):
            return "Missing required parameter: \(param)"
        case .invalidParameter(let param, let reason):
            return "Invalid parameter '\(param)': \(reason)"
        }
    }
}

// MARK: - Email MCP Server

/// Exposes email tools (send, reply, search, read, attachments) that integrate with MCPManager.
actor EmailMCPServer {
    private let agentMailClient: AgentMailClient
    private let attachmentProcessor: AttachmentProcessor

    /// The server name used when registering tools with MCPManager.
    static let serverName = "email"

    init(agentMailClient: AgentMailClient, attachmentProcessor: AttachmentProcessor) {
        self.agentMailClient = agentMailClient
        self.attachmentProcessor = attachmentProcessor
    }

    // MARK: - Tool Registration

    func getToolDefinitions() -> [EmailToolDefinition] {
        [
            EmailToolDefinition(
                name: "send_email",
                description: "Send a new email via AgentMail. Supports multiple recipients (comma-separated) and optional CC/BCC fields.",
                parameters: [
                    EmailToolParameter(name: "to", type: "string", description: "Recipient email addresses, comma-separated", required: true),
                    EmailToolParameter(name: "subject", type: "string", description: "Email subject line", required: true),
                    EmailToolParameter(name: "body", type: "string", description: "Email body content (plain text)", required: true),
                    EmailToolParameter(name: "cc", type: "string", description: "CC email addresses, comma-separated", required: false),
                    EmailToolParameter(name: "bcc", type: "string", description: "BCC email addresses, comma-separated", required: false),
                ]
            ),
            EmailToolDefinition(
                name: "reply_to_email",
                description: "Reply to an existing email thread. The reply is sent to the original sender with proper threading.",
                parameters: [
                    EmailToolParameter(name: "emailMessageId", type: "string", description: "The message ID to reply to", required: true),
                    EmailToolParameter(name: "body", type: "string", description: "Reply body content (plain text)", required: true),
                ]
            ),
            EmailToolDefinition(
                name: "search_emails",
                description: "List recent emails from the inbox. Returns a list of emails with subject, sender, date, and snippet.",
                parameters: [
                    EmailToolParameter(name: "maxResults", type: "integer", description: "Maximum number of results to return (default: 10, max: 50)", required: false),
                ]
            ),
            EmailToolDefinition(
                name: "get_email",
                description: "Get the full content of a specific email by its message ID, including headers, body text, and attachment metadata.",
                parameters: [
                    EmailToolParameter(name: "emailMessageId", type: "string", description: "The message ID to retrieve", required: true),
                ]
            ),
            EmailToolDefinition(
                name: "get_attachment",
                description: "Download and process an email attachment. PDFs are converted to text, images are stored locally, and text/CSV/JSON content is returned directly.",
                parameters: [
                    EmailToolParameter(name: "emailMessageId", type: "string", description: "The message ID containing the attachment", required: true),
                    EmailToolParameter(name: "attachmentId", type: "string", description: "The attachment ID to retrieve", required: true),
                ]
            ),
        ]
    }

    /// Convert tool definitions to MCPToolInfo format for registration with MCPManager.
    func getMCPToolInfos() -> [MCPToolInfo] {
        getToolDefinitions().map { def in
            let schema = buildInputSchema(from: def)
            let inferred = ToolTypeInference.infer(name: def.name, description: def.description, inputSchema: schema)
            return MCPToolInfo(
                name: def.name,
                description: def.description,
                inputSchema: schema,
                serverName: Self.serverName,
                outputType: inferred.output,
                acceptsInputTypes: inferred.accepts
            )
        }
    }

    /// Convert tool definitions to ToolDefinition format for the Claude API.
    func getClaudeToolDefinitions() -> [ToolDefinition] {
        getToolDefinitions().map { def in
            ToolDefinition(
                name: def.name,
                description: def.description,
                input_schema: buildInputSchema(from: def)
            )
        }
    }

    // MARK: - Tool Call Dispatch

    func callTool(name: String, arguments: [String: String]) async throws -> EmailToolResult {
        Logger.info("EmailMCPServer: calling tool '\(name)' with \(arguments.count) argument(s)")

        switch name {
        case "send_email":
            return await handleSendEmail(arguments: arguments)
        case "reply_to_email":
            return await handleReplyToEmail(arguments: arguments)
        case "search_emails":
            return await handleSearchEmails(arguments: arguments)
        case "get_email":
            return await handleGetEmail(arguments: arguments)
        case "get_attachment":
            return await handleGetAttachment(arguments: arguments)
        default:
            Logger.error("EmailMCPServer: unknown tool '\(name)'")
            return .error("Unknown email tool: \(name)")
        }
    }

    /// Handle a tool call using JSONValue arguments (compatible with MCPManager routing).
    func callTool(name: String, arguments: JSONValue) async throws -> MCPToolCallResult {
        let stringArgs = extractStringArguments(from: arguments)
        let result = try await callTool(name: name, arguments: stringArgs)
        return MCPToolCallResult(content: result.content, isError: result.isError)
    }

    // MARK: - Tool Implementations

    private func handleSendEmail(arguments: [String: String]) async -> EmailToolResult {
        guard let toRaw = arguments["to"], !toRaw.isEmpty else {
            return .error("Missing required parameter: to")
        }
        guard let subject = arguments["subject"], !subject.isEmpty else {
            return .error("Missing required parameter: subject")
        }
        guard let body = arguments["body"], !body.isEmpty else {
            return .error("Missing required parameter: body")
        }

        let toAddresses = parseCommaSeparatedEmails(toRaw)
        if toAddresses.isEmpty {
            return .error("Invalid 'to' parameter: no valid email addresses found")
        }

        let ccAddresses: [String]? = arguments["cc"].map { parseCommaSeparatedEmails($0) }
        let bccAddresses: [String]? = arguments["bcc"].map { parseCommaSeparatedEmails($0) }

        do {
            let messageId = try await agentMailClient.sendEmail(
                to: toAddresses,
                subject: subject,
                body: body,
                cc: ccAddresses,
                bcc: bccAddresses
            )
            Logger.info("EmailMCPServer: email sent successfully, messageId=\(messageId)")
            return .success("Email sent successfully. Message ID: \(messageId)")
        } catch {
            Logger.error("EmailMCPServer: send_email failed: \(error)")
            return .error("Failed to send email: \(error.localizedDescription)")
        }
    }

    private func handleReplyToEmail(arguments: [String: String]) async -> EmailToolResult {
        guard let messageId = arguments["emailMessageId"], !messageId.isEmpty else {
            return .error("Missing required parameter: emailMessageId")
        }
        guard let body = arguments["body"], !body.isEmpty else {
            return .error("Missing required parameter: body")
        }

        do {
            let originalMessage = try await agentMailClient.getMessage(id: messageId)

            let replyId = try await agentMailClient.replyToEmail(
                messageId: messageId,
                threadId: originalMessage.threadId,
                body: body
            )
            Logger.info("EmailMCPServer: reply sent successfully, messageId=\(replyId)")
            return .success("Reply sent successfully. Message ID: \(replyId)")
        } catch {
            Logger.error("EmailMCPServer: reply_to_email failed: \(error)")
            return .error("Failed to reply to email: \(error.localizedDescription)")
        }
    }

    private func handleSearchEmails(arguments: [String: String]) async -> EmailToolResult {
        let maxResults: Int
        if let maxStr = arguments["maxResults"], let parsed = Int(maxStr) {
            maxResults = min(max(parsed, 1), 50)
        } else {
            maxResults = 10
        }

        do {
            let messages = try await agentMailClient.listMessages(limit: maxResults)

            if messages.isEmpty {
                return .success("No emails found in inbox.")
            }

            var emailSummaries: [String] = []
            for message in messages {
                let summary = formatEmailSummary(message)
                emailSummaries.append(summary)
            }

            let header = "Found \(emailSummaries.count) email(s):\n"
            let separator = String(repeating: "-", count: 60)
            let body = emailSummaries.joined(separator: "\n\(separator)\n")

            Logger.info("EmailMCPServer: search returned \(emailSummaries.count) result(s)")
            return .success("\(header)\(separator)\n\(body)")

        } catch {
            Logger.error("EmailMCPServer: search_emails failed: \(error)")
            return .error("Failed to search emails: \(error.localizedDescription)")
        }
    }

    private func handleGetEmail(arguments: [String: String]) async -> EmailToolResult {
        guard let messageId = arguments["emailMessageId"], !messageId.isEmpty else {
            return .error("Missing required parameter: emailMessageId")
        }

        do {
            let message = try await agentMailClient.getMessage(id: messageId)
            let formatted = formatEmailFull(message)

            Logger.info("EmailMCPServer: retrieved email \(messageId)")
            return .success(formatted)
        } catch {
            Logger.error("EmailMCPServer: get_email failed for \(messageId): \(error)")
            return .error("Failed to get email: \(error.localizedDescription)")
        }
    }

    private func handleGetAttachment(arguments: [String: String]) async -> EmailToolResult {
        guard let messageId = arguments["emailMessageId"], !messageId.isEmpty else {
            return .error("Missing required parameter: emailMessageId")
        }
        guard let attachmentId = arguments["attachmentId"], !attachmentId.isEmpty else {
            return .error("Missing required parameter: attachmentId")
        }

        do {
            let message = try await agentMailClient.getMessage(id: messageId)
            guard let attachmentMeta = message.attachments.first(where: { $0.id == attachmentId }) else {
                return .error("Attachment '\(attachmentId)' not found in message '\(messageId)'")
            }

            let data = try await agentMailClient.getAttachment(
                messageId: messageId,
                attachmentId: attachmentId
            )

            let processed = try await attachmentProcessor.process(
                emailId: messageId,
                attachmentId: attachmentId,
                filename: attachmentMeta.filename,
                mimeType: attachmentMeta.mimeType,
                data: data
            )

            Logger.info("EmailMCPServer: processed attachment \(attachmentMeta.filename) from \(messageId)")
            return .success(processed.summary)

        } catch {
            Logger.error("EmailMCPServer: get_attachment failed for \(messageId)/\(attachmentId): \(error)")
            return .error("Failed to get attachment: \(error.localizedDescription)")
        }
    }

    // MARK: - Formatting Helpers

    private func formatEmailSummary(_ message: EmailMessage) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let date = formatter.string(from: message.receivedAt)
        let attachmentNote = message.attachments.isEmpty ? "" : " [\(message.attachments.count) attachment(s)]"
        let bodySnippet = String(message.bodyText.prefix(150))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        return """
        ID: \(message.id)
        From: \(message.from)
        Subject: \(message.subject)
        Date: \(date)\(attachmentNote)
        Preview: \(bodySnippet)
        """
    }

    private func formatEmailFull(_ message: EmailMessage) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .long

        let date = formatter.string(from: message.receivedAt)
        let to = message.to.joined(separator: ", ")
        let cc = message.cc.isEmpty ? "" : "\nCC: \(message.cc.joined(separator: ", "))"
        let labels = message.labels.isEmpty ? "" : "\nLabels: \(message.labels.joined(separator: ", "))"

        var result = """
        Message ID: \(message.id)
        Thread ID: \(message.threadId)
        From: \(message.from)
        To: \(to)\(cc)
        Subject: \(message.subject)
        Date: \(date)\(labels)
        """

        if !message.attachments.isEmpty {
            result += "\n\nAttachments:"
            for attachment in message.attachments {
                let sizeMB = String(format: "%.1f", Double(attachment.size) / 1_048_576.0)
                let sizeKB = String(format: "%.1f", Double(attachment.size) / 1_024.0)
                let sizeStr = attachment.size > 1_048_576 ? "\(sizeMB) MB" : "\(sizeKB) KB"
                result += "\n  - \(attachment.filename) (\(attachment.mimeType), \(sizeStr)) [ID: \(attachment.id)]"
            }
        }

        result += "\n\n--- Body ---\n\(message.bodyText)"

        return result
    }

    // MARK: - Argument Parsing Helpers

    private func parseCommaSeparatedEmails(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func extractStringArguments(from arguments: JSONValue) -> [String: String] {
        guard case .object(let obj) = arguments else {
            return [:]
        }

        var result: [String: String] = [:]
        for (key, value) in obj {
            switch value {
            case .string(let s):
                result[key] = s
            case .int(let i):
                result[key] = String(i)
            case .double(let d):
                result[key] = String(d)
            case .bool(let b):
                result[key] = String(b)
            default:
                result[key] = value.toJSONString()
            }
        }
        return result
    }

    private func buildInputSchema(from definition: EmailToolDefinition) -> JSONValue {
        var properties: [String: JSONValue] = [:]
        var required: [JSONValue] = []

        for param in definition.parameters {
            let propDict: [String: JSONValue] = [
                "type": .string(param.type),
                "description": .string(param.description),
            ]

            properties[param.name] = .object(propDict)

            if param.required {
                required.append(.string(param.name))
            }
        }

        return .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required),
        ])
    }
}
