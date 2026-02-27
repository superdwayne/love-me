import Foundation

/// Thread mapping persisted to `~/.love-me/email-threads.json`.
/// Maps Gmail thread IDs to conversation IDs so subsequent emails in the same thread
/// append to the existing conversation rather than creating a new one.
struct EmailThreadMapping: Codable, Sendable {
    var threadToConversation: [String: String]
}

// MARK: - Bridge Errors

enum EmailConversationBridgeError: Error, LocalizedError {
    case conversationNotFound(String)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .conversationNotFound(let id):
            return "Conversation not found: \(id)"
        case .persistenceFailed(let detail):
            return "Failed to persist thread mapping: \(detail)"
        }
    }
}

/// Bridges incoming emails to the conversation system.
///
/// Responsibilities:
/// - Creates new conversations from incoming emails (or appends to existing thread conversations)
/// - Formats email content as a system-readable summary message
/// - Evaluates `EmailTriggerRule`s and executes matching workflows
/// - Persists threadId-to-conversationId mapping for thread continuity
actor EmailConversationBridge {

    // MARK: - Dependencies

    private let conversationStore: ConversationStore
    private let triggerStore: EmailTriggerStore
    private let workflowStore: WorkflowStore
    private let workflowExecutor: WorkflowExecutor
    private let eventBus: EventBus

    // MARK: - State

    private var threadMapping: EmailThreadMapping
    private let mappingFilePath: String

    // MARK: - JSON Coding

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    // MARK: - Init

    /// - Parameters:
    ///   - conversationStore: The conversation persistence layer.
    ///   - triggerStore: The email trigger rules store.
    ///   - workflowStore: The workflow definitions store.
    ///   - workflowExecutor: The workflow execution engine.
    ///   - eventBus: The event bus (for future event-driven integrations).
    ///   - basePath: Base directory path (e.g. `~/.love-me`). Thread mapping stored at `<basePath>/email-threads.json`.
    init(
        conversationStore: ConversationStore,
        triggerStore: EmailTriggerStore,
        workflowStore: WorkflowStore,
        workflowExecutor: WorkflowExecutor,
        eventBus: EventBus,
        basePath: String
    ) {
        self.conversationStore = conversationStore
        self.triggerStore = triggerStore
        self.workflowStore = workflowStore
        self.workflowExecutor = workflowExecutor
        self.eventBus = eventBus

        self.mappingFilePath = "\(basePath)/email-threads.json"
        self.threadMapping = EmailThreadMapping(threadToConversation: [:])

        // Load persisted mapping inline (safe because we only read our own stored properties)
        if let data = try? Data(contentsOf: URL(fileURLWithPath: self.mappingFilePath)),
           let loaded = try? self.decoder.decode(EmailThreadMapping.self, from: data) {
            self.threadMapping = loaded
        }
    }

    // MARK: - Public API

    /// Handle an incoming email. This is the primary entry point, intended to be wired as
    /// `EmailPollingService.onEmailReceived`.
    ///
    /// 1. Creates or locates the conversation for this email thread.
    /// 2. Adds a formatted email summary message to the conversation.
    /// 3. Evaluates trigger rules and executes matching workflows.
    func handleIncomingEmail(_ email: EmailMessage) async {
        Logger.info("EmailConversationBridge: handling email '\(email.subject)' from \(email.from) (thread: \(email.threadId))")

        do {
            let conversationId = try await resolveConversation(for: email)

            // Format and add the email summary message
            let summaryContent = formatEmailSummary(email)
            let metadata: [String: String] = [
                "sourceType": "email",
                "emailThreadId": email.threadId,
                "emailMessageId": email.id,
                "fromAddress": email.from,
            ]
            let message = StoredMessage(
                role: "user",
                content: summaryContent,
                timestamp: email.receivedAt,
                metadata: metadata
            )
            _ = try await conversationStore.addMessage(to: conversationId, message: message)

            Logger.info("EmailConversationBridge: added email to conversation \(conversationId)")

            // Evaluate trigger rules asynchronously (don't block the conversation creation)
            await evaluateTriggers(for: email)

        } catch {
            Logger.error("EmailConversationBridge: failed to handle email \(email.id): \(error)")
        }
    }

    /// Look up the conversation ID for a given thread, if one exists.
    func conversationId(forThread threadId: String) -> String? {
        threadMapping.threadToConversation[threadId]
    }

    // MARK: - Conversation Resolution

    /// Find the existing conversation for this thread, or create a new one.
    /// Returns the conversation ID.
    private func resolveConversation(for email: EmailMessage) async throws -> String {
        // Check if we already have a conversation for this thread
        if let existingId = threadMapping.threadToConversation[email.threadId] {
            // Verify the conversation still exists
            do {
                _ = try await conversationStore.load(id: existingId)
                Logger.info("EmailConversationBridge: appending to existing conversation \(existingId) for thread \(email.threadId)")
                return existingId
            } catch {
                // Conversation was deleted; remove stale mapping and create a new one
                Logger.info("EmailConversationBridge: stale mapping for thread \(email.threadId), creating new conversation")
                threadMapping.threadToConversation.removeValue(forKey: email.threadId)
            }
        }

        // Create a new conversation with the email subject as the title
        let conversation = try await conversationStore.create(title: email.subject)
        threadMapping.threadToConversation[email.threadId] = conversation.id
        persistMapping()

        Logger.info("EmailConversationBridge: created conversation \(conversation.id) for thread \(email.threadId)")
        return conversation.id
    }

    // MARK: - Email Formatting

    /// Format an email into a human-readable summary suitable as a conversation message.
    private func formatEmailSummary(_ email: EmailMessage) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var lines: [String] = []
        lines.append("[Email Received]")
        lines.append("From: \(email.from)")
        lines.append("To: \(email.to.joined(separator: ", "))")
        if !email.cc.isEmpty {
            lines.append("CC: \(email.cc.joined(separator: ", "))")
        }
        lines.append("Subject: \(email.subject)")
        lines.append("Date: \(dateFormatter.string(from: email.receivedAt))")

        if !email.labels.isEmpty {
            lines.append("Labels: \(email.labels.joined(separator: ", "))")
        }

        if !email.attachments.isEmpty {
            lines.append("")
            lines.append("Attachments:")
            for attachment in email.attachments {
                let sizeKB = attachment.size / 1024
                lines.append("  - \(attachment.filename) (\(attachment.mimeType), \(sizeKB)KB)")
            }
        }

        lines.append("")
        lines.append("--- Body ---")

        // Truncate body to 4000 characters
        let bodyText = email.bodyText
        if bodyText.count > 4000 {
            let truncated = String(bodyText.prefix(4000))
            lines.append(truncated)
            lines.append("\n[... body truncated at 4000 characters ...]")
        } else {
            lines.append(bodyText)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Trigger Evaluation

    /// Evaluate all enabled trigger rules against the incoming email.
    /// For each matching rule, execute the associated workflow.
    private func evaluateTriggers(for email: EmailMessage) async {
        let rules = await triggerStore.listAll()
        let matchingRules = rules.filter { $0.enabled && $0.conditions.matches(email) }

        if matchingRules.isEmpty {
            Logger.info("EmailConversationBridge: no trigger rules matched for email \(email.id)")
            return
        }

        Logger.info("EmailConversationBridge: \(matchingRules.count) trigger rule(s) matched for email \(email.id)")

        for rule in matchingRules {
            do {
                let workflow = try await workflowStore.get(id: rule.workflowId)
                guard workflow.enabled else {
                    Logger.info("EmailConversationBridge: skipping disabled workflow '\(workflow.name)' for trigger \(rule.id)")
                    continue
                }

                let triggerInfo = "email_trigger: rule=\(rule.id), from=\(email.from), subject=\(email.subject)"
                Logger.info("EmailConversationBridge: executing workflow '\(workflow.name)' triggered by email from \(email.from)")

                // Execute in a detached task so we don't block email processing
                let executor = self.workflowExecutor
                Task {
                    let execution = await executor.execute(workflow: workflow, triggerInfo: triggerInfo)
                    switch execution.status {
                    case .completed:
                        Logger.info("EmailConversationBridge: workflow '\(workflow.name)' completed for email trigger")
                    case .failed:
                        Logger.error("EmailConversationBridge: workflow '\(workflow.name)' failed for email trigger")
                    default:
                        break
                    }
                }
            } catch {
                Logger.error("EmailConversationBridge: failed to load workflow \(rule.workflowId) for trigger \(rule.id): \(error)")
            }
        }
    }

    // MARK: - Persistence

    /// Persist the thread-to-conversation mapping to disk.
    private func persistMapping() {
        do {
            let data = try encoder.encode(threadMapping)
            try data.write(to: URL(fileURLWithPath: mappingFilePath), options: .atomic)
        } catch {
            Logger.error("EmailConversationBridge: failed to persist thread mapping: \(error)")
        }
    }
}
