import Foundation

/// Handles incoming emails: evaluates trigger rules and creates unified approval cards.
///
/// Previously this bridge classified emails and pre-built workflows. Now it performs
/// a lightweight summarize-only Claude call, creating a single unified approval that
/// lets the user choose between Chat or Auto Workflow on the client side.
actor EmailConversationBridge {

    // MARK: - Dependencies

    private let triggerStore: EmailTriggerStore
    private let workflowStore: WorkflowStore
    private let workflowExecutor: WorkflowExecutor
    private let eventBus: EventBus
    private let approvalStore: EmailApprovalStore
    private let agentMailClient: AgentMailClient?
    private let attachmentProcessor: AttachmentProcessor?

    // MARK: - Callbacks

    /// Classifies an email using Claude. Input: email text. Output: raw classification response.
    typealias EmailClassifier = @Sendable (String) async throws -> String

    private var classifyEmail: EmailClassifier?

    /// Called when a new approval is created — broadcasts to connected clients.
    typealias ApprovalCreatedHandler = @Sendable (PendingEmailApproval) async -> Void

    private var onApprovalCreated: ApprovalCreatedHandler?

    // MARK: - Init

    init(
        triggerStore: EmailTriggerStore,
        workflowStore: WorkflowStore,
        workflowExecutor: WorkflowExecutor,
        eventBus: EventBus,
        approvalStore: EmailApprovalStore,
        agentMailClient: AgentMailClient? = nil,
        attachmentProcessor: AttachmentProcessor? = nil
    ) {
        self.triggerStore = triggerStore
        self.workflowStore = workflowStore
        self.workflowExecutor = workflowExecutor
        self.eventBus = eventBus
        self.approvalStore = approvalStore
        self.agentMailClient = agentMailClient
        self.attachmentProcessor = attachmentProcessor
    }

    // MARK: - Configuration

    func setClassifyEmail(_ classifier: @escaping EmailClassifier) {
        self.classifyEmail = classifier
    }

    func setOnApprovalCreated(_ handler: @escaping ApprovalCreatedHandler) {
        self.onApprovalCreated = handler
    }

    // MARK: - Public API

    /// Handle an incoming email. This is the primary entry point, intended to be wired as
    /// `EmailPollingService.onEmailReceived`.
    ///
    /// 1. Auto-processes attachments (PDF text extraction, image storage, etc.).
    /// 2. Evaluates trigger rules and executes matching workflows.
    /// 3. Summarizes the email and creates a unified approval for user review.
    func handleIncomingEmail(_ email: EmailMessage, conversationId: String? = nil) async {
        Logger.info("EmailConversationBridge: handling email '\(email.subject)' from \(email.from)")

        // Auto-process attachments in background (download + extract text/images)
        var attachmentSummaries: [String] = []
        if !email.attachments.isEmpty {
            attachmentSummaries = await autoProcessAttachments(email)
        }

        // Evaluate trigger rules (these still auto-execute)
        await evaluateTriggers(for: email)

        // Summarize and create unified approval (include attachment info)
        await summarizeAndCreateApproval(email, attachmentSummaries: attachmentSummaries, conversationId: conversationId)
    }

    // MARK: - Attachment Auto-Processing

    /// Download and process all attachments for an email. Returns a summary per attachment.
    private func autoProcessAttachments(_ email: EmailMessage) async -> [String] {
        guard let client = agentMailClient, let processor = attachmentProcessor else {
            Logger.info("EmailConversationBridge: skipping attachment processing (client or processor not configured)")
            return []
        }

        var summaries: [String] = []

        for attachment in email.attachments {
            do {
                let data = try await client.getAttachment(
                    messageId: email.id,
                    attachmentId: attachment.id
                )

                let processed = try await processor.process(
                    emailId: email.id,
                    attachmentId: attachment.id,
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    data: data
                )

                Logger.info("EmailConversationBridge: processed attachment '\(attachment.filename)' (\(processed.contentType))")
                summaries.append("[\(attachment.filename)] \(processed.summary)")

            } catch {
                Logger.error("EmailConversationBridge: failed to process attachment '\(attachment.filename)': \(error)")
                summaries.append("[\(attachment.filename)] Failed to process: \(error.localizedDescription)")
            }
        }

        return summaries
    }

    // MARK: - Email Summarization

    private func summarizeAndCreateApproval(_ email: EmailMessage, attachmentSummaries: [String] = [], conversationId: String?) async {
        guard let classifier = classifyEmail else {
            Logger.error("EmailConversationBridge: classifier not configured, creating approval with no summary")
            await createUnifiedApproval(email, summary: nil, recommendation: "chat", conversationId: conversationId)
            return
        }

        var attachmentInfo = ""
        if !email.attachments.isEmpty {
            let attachmentLines = email.attachments.map { att in
                let sizeMB = String(format: "%.1f", Double(att.size) / 1_048_576.0)
                let sizeKB = String(format: "%.1f", Double(att.size) / 1_024.0)
                let sizeStr = att.size > 1_048_576 ? "\(sizeMB) MB" : "\(sizeKB) KB"
                return "  - \(att.filename) (\(att.mimeType), \(sizeStr))"
            }
            attachmentInfo = "\nAttachments (\(email.attachments.count)):\n\(attachmentLines.joined(separator: "\n"))"

            // Include processed attachment content (e.g. extracted PDF text)
            if !attachmentSummaries.isEmpty {
                attachmentInfo += "\n\nProcessed Attachment Content:\n\(attachmentSummaries.joined(separator: "\n"))"
            }
        }

        let prompt = """
        Analyze this email briefly. Respond with ONLY a JSON object.

        Email:
        From: \(email.from)
        Subject: \(email.subject)\(attachmentInfo)
        Body:
        \(String(email.bodyText.prefix(4000)))

        Respond with JSON:
        {
          "summary": "one sentence summary of what this email is about",
          "recommendation": "chat" or "workflow" or "dismiss"
        }

        Recommendation rules:
        - "workflow": The email describes a clear, actionable task that could be automated (includes emails with attachments to process)
        - "chat": The email needs discussion, clarification, or a nuanced response
        - "dismiss": Spam, newsletters, notifications, or auto-generated messages that need no response
        """

        do {
            let response = try await classifier(prompt)
            let result = parseSummaryResponse(response)

            if result.recommendation == "dismiss" {
                Logger.info("EmailConversationBridge: recommended dismiss for '\(email.subject)', skipping approval")
                return
            }

            await createUnifiedApproval(
                email,
                summary: result.summary,
                recommendation: result.recommendation,
                conversationId: conversationId
            )
        } catch {
            Logger.error("EmailConversationBridge: summarization failed, creating approval anyway: \(error)")
            await createUnifiedApproval(email, summary: nil, recommendation: "chat", conversationId: conversationId)
        }
    }

    private struct SummaryResult {
        let summary: String?
        let recommendation: String
    }

    private func parseSummaryResponse(_ response: String) -> SummaryResult {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.error("EmailConversationBridge: failed to parse summary response, defaulting to chat")
            return SummaryResult(summary: nil, recommendation: "chat")
        }

        let recommendation: String
        if let rec = json["recommendation"] as? String,
           ["chat", "workflow", "dismiss"].contains(rec.lowercased()) {
            recommendation = rec.lowercased()
        } else {
            recommendation = "chat"
        }

        return SummaryResult(
            summary: json["summary"] as? String,
            recommendation: recommendation
        )
    }

    // MARK: - Unified Approval Creation

    private func createUnifiedApproval(
        _ email: EmailMessage,
        summary: String?,
        recommendation: String,
        conversationId: String?
    ) async {
        let emailSummary = EmailMessageSummary(from: email)
        let approval = PendingEmailApproval(
            email: emailSummary,
            classification: .workflow,
            conversationId: conversationId,
            summary: summary,
            recommendation: recommendation
        )

        do {
            try await approvalStore.add(approval)

            if let handler = onApprovalCreated {
                await handler(approval)
            }
        } catch {
            Logger.error("EmailConversationBridge: failed to create approval: \(error)")
        }
    }

    // MARK: - Trigger Evaluation

    /// Evaluate all enabled trigger rules against the incoming email.
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
}
