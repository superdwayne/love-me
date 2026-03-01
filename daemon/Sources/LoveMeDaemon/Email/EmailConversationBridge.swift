import Foundation

/// Handles incoming emails: evaluates trigger rules and auto-creates workflows from email briefs.
actor EmailConversationBridge {

    // MARK: - Dependencies

    private let triggerStore: EmailTriggerStore
    private let workflowStore: WorkflowStore
    private let workflowExecutor: WorkflowExecutor
    private let eventBus: EventBus

    // MARK: - Callbacks

    /// Called when a workflow is auto-created from an email brief.
    typealias BriefWorkflowHandler = @Sendable (String, String, String) async -> Void  // workflowId, workflowName, emailSubject

    /// Set via `setOnBriefWorkflowCreated(_:)` to broadcast to connected clients.
    private var onBriefWorkflowCreated: BriefWorkflowHandler?

    /// Reference to the workflow builder (injected from DaemonApp).
    typealias WorkflowBuilder = @Sendable (String) async throws -> WorkflowDefinition?

    private var buildWorkflowFromPrompt: WorkflowBuilder?

    // MARK: - Init

    init(
        triggerStore: EmailTriggerStore,
        workflowStore: WorkflowStore,
        workflowExecutor: WorkflowExecutor,
        eventBus: EventBus
    ) {
        self.triggerStore = triggerStore
        self.workflowStore = workflowStore
        self.workflowExecutor = workflowExecutor
        self.eventBus = eventBus
    }

    // MARK: - Configuration

    func setOnBriefWorkflowCreated(_ handler: @escaping BriefWorkflowHandler) {
        self.onBriefWorkflowCreated = handler
    }

    func setWorkflowBuilder(_ builder: @escaping WorkflowBuilder) {
        self.buildWorkflowFromPrompt = builder
    }

    // MARK: - Public API

    /// Handle an incoming email. This is the primary entry point, intended to be wired as
    /// `EmailPollingService.onEmailReceived`.
    ///
    /// 1. Evaluates trigger rules and executes matching workflows.
    /// 2. Auto-creates a workflow from the email brief using Claude.
    func handleIncomingEmail(_ email: EmailMessage) async {
        Logger.info("EmailConversationBridge: handling email '\(email.subject)' from \(email.from)")

        // Evaluate trigger rules
        await evaluateTriggers(for: email)

        // Auto-create workflow from email brief
        await createAndExecuteWorkflowFromBrief(email)
    }

    // MARK: - Auto-Workflow from Brief

    /// Build a prompt from the email, call Claude to generate a workflow, save it, and execute.
    private func createAndExecuteWorkflowFromBrief(_ email: EmailMessage) async {
        guard let builder = buildWorkflowFromPrompt else {
            Logger.error("EmailConversationBridge: workflow builder not configured")
            return
        }

        let prompt = """
        Analyze this email brief and create a workflow to accomplish what it describes.

        From: \(email.from)
        Subject: \(email.subject)
        Body:
        \(String(email.bodyText.prefix(4000)))
        """

        do {
            guard let workflow = try await builder(prompt) else {
                Logger.info("EmailConversationBridge: builder returned nil for email '\(email.subject)'")
                return
            }

            // Save the workflow
            try await workflowStore.create(workflow)
            Logger.info("EmailConversationBridge: created workflow '\(workflow.name)' from email brief")

            // Notify connected clients
            if let handler = onBriefWorkflowCreated {
                await handler(workflow.id, workflow.name, email.subject)
            }

            // Execute immediately
            let executor = self.workflowExecutor
            Task {
                let execution = await executor.execute(workflow: workflow, triggerInfo: "email_brief: \(email.subject)")
                switch execution.status {
                case .completed:
                    Logger.info("EmailConversationBridge: workflow '\(workflow.name)' completed from email brief")
                case .failed:
                    Logger.error("EmailConversationBridge: workflow '\(workflow.name)' failed from email brief")
                default:
                    break
                }
            }
        } catch {
            Logger.error("EmailConversationBridge: failed to create workflow from email brief: \(error)")
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
