import Foundation

/// Sends workflow notifications to connected iOS clients via WebSocket.
actor NotificationService {
    private let server: WebSocketServer

    init(server: WebSocketServer) {
        self.server = server
    }

    // MARK: - Public API

    /// Notify about workflow execution start
    func notifyWorkflowStarted(execution: WorkflowExecution, prefs: NotificationPrefs) async {
        guard prefs.notifyOnStart else { return }

        let title = "Workflow Started"
        let body = "\(execution.workflowName) is now running."

        Logger.info("Notification: workflow \(execution.workflowName) started (execution: \(execution.id))")
        await send(
            title: title,
            body: body,
            workflowId: execution.workflowId,
            executionId: execution.id,
            notificationType: "started"
        )
    }

    /// Notify about workflow execution completion
    func notifyWorkflowCompleted(execution: WorkflowExecution, prefs: NotificationPrefs) async {
        guard prefs.notifyOnComplete else { return }

        let title = "Workflow Completed"
        let body = "\(execution.workflowName) finished successfully."

        Logger.info("Notification: workflow \(execution.workflowName) completed (execution: \(execution.id))")
        await send(
            title: title,
            body: body,
            workflowId: execution.workflowId,
            executionId: execution.id,
            notificationType: "completed"
        )
    }

    /// Notify about workflow execution failure
    func notifyWorkflowFailed(execution: WorkflowExecution, prefs: NotificationPrefs) async {
        guard prefs.notifyOnError else { return }

        let title = "Workflow Failed"
        let body = "\(execution.workflowName) encountered an error."

        Logger.info("Notification: workflow \(execution.workflowName) failed (execution: \(execution.id))")
        await send(
            title: title,
            body: body,
            workflowId: execution.workflowId,
            executionId: execution.id,
            notificationType: "failed"
        )
    }

    /// Notify about step completion
    func notifyStepCompleted(execution: WorkflowExecution, step: StepResult, prefs: NotificationPrefs) async {
        guard prefs.notifyOnStepComplete else { return }

        let title = "Step Completed"
        let body = "\(step.stepName) finished in \(execution.workflowName)."

        Logger.info("Notification: step \(step.stepName) completed in workflow \(execution.workflowName) (execution: \(execution.id))")
        await send(
            title: title,
            body: body,
            workflowId: execution.workflowId,
            executionId: execution.id,
            notificationType: "stepCompleted"
        )
    }

    // MARK: - Private

    private func send(
        title: String,
        body: String,
        workflowId: String,
        executionId: String,
        notificationType: String
    ) async {
        let message = WSMessage(
            type: WSMessageType.workflowNotification,
            metadata: [
                "title": .string(title),
                "body": .string(body),
                "workflowId": .string(workflowId),
                "executionId": .string(executionId),
                "notificationType": .string(notificationType),
            ]
        )

        await server.broadcast(message)
    }
}
