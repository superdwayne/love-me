import SwiftUI

struct WorkflowDetailView: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    @Environment(\.dismiss) private var dismiss
    let workflowId: String

    @State private var showEditor = false
    @State private var showDeleteAlert = false
    @State private var appeared = false

    private var workflow: WorkflowDetail? {
        workflowVM.currentWorkflow
    }

    var body: some View {
        ScrollView {
            if let workflow {
                VStack(spacing: LoveMeTheme.lg) {
                    headerCard(workflow)
                    scheduleCard(workflow)
                    stepsCard(workflow)
                    executionsSection
                    actionsCard(workflow)
                }
                .padding(LoveMeTheme.lg)
            } else if workflowVM.isLoading {
                VStack(spacing: LoveMeTheme.lg) {
                    Spacer().frame(height: 100)
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.trust)
                    Text("Loading workflow...")
                        .font(.chatMessage)
                        .foregroundStyle(.trust)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(.appBackground)
        .navigationTitle(workflow?.name ?? "Workflow")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEditor = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.trust)
                }
            }
        }
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            workflowVM.loadWorkflow(id: workflowId)
            workflowVM.loadExecutions(workflowId: workflowId)
            withAnimation(.easeOut(duration: LoveMeTheme.appearDuration)) {
                appeared = true
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                WorkflowEditorView(existingWorkflow: workflow)
            }
        }
        .alert("Delete Workflow", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                workflowVM.deleteWorkflow(id: workflowId)
                dismiss()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Header

    private func headerCard(_ workflow: WorkflowDetail) -> some View {
        VStack(alignment: .leading, spacing: LoveMeTheme.md) {
            HStack {
                VStack(alignment: .leading, spacing: LoveMeTheme.xs) {
                    Text(workflow.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.textPrimary)

                    if !workflow.description.isEmpty {
                        Text(workflow.description)
                            .font(.chatMessage)
                            .foregroundStyle(.trust)
                    }
                }

                Spacer()

                // Enabled toggle
                Toggle("", isOn: Binding(
                    get: { workflow.enabled },
                    set: { _ in
                        workflowVM.toggleWorkflowEnabled(id: workflow.id)
                    }
                ))
                .labelsHidden()
                .tint(.heart)
            }
        }
        .padding(LoveMeTheme.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Schedule

    private func scheduleCard(_ workflow: WorkflowDetail) -> some View {
        VStack(alignment: .leading, spacing: LoveMeTheme.sm) {
            Text("SCHEDULE")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)

            HStack(spacing: LoveMeTheme.sm) {
                Image(systemName: "clock")
                    .font(.system(size: 16))
                    .foregroundStyle(.electricBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workflow.trigger.type.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.electricBlue)

                    if let cron = workflow.trigger.cronExpression, !cron.isEmpty {
                        Text(cron)
                            .font(.toolDetail)
                            .foregroundStyle(.textPrimary)
                    }

                    if let source = workflow.trigger.eventSource {
                        Text("\(source):\(workflow.trigger.eventType ?? "")")
                            .font(.toolDetail)
                            .foregroundStyle(.textPrimary)
                    }
                }

                Spacer()
            }
        }
        .padding(LoveMeTheme.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Steps

    private func stepsCard(_ workflow: WorkflowDetail) -> some View {
        VStack(alignment: .leading, spacing: LoveMeTheme.md) {
            HStack {
                Text("STEPS")
                    .font(.sectionHeader)
                    .foregroundStyle(.trust)
                    .tracking(1.2)

                Spacer()

                Text("\(workflow.steps.count)")
                    .font(.toolDetail)
                    .foregroundStyle(.trust)
                    .padding(.horizontal, LoveMeTheme.sm)
                    .padding(.vertical, 2)
                    .background(Color.surfaceElevated)
                    .clipShape(Capsule())
            }

            VStack(spacing: 0) {
                ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(step, index: index)

                    if index < workflow.steps.count - 1 {
                        HStack {
                            Rectangle()
                                .fill(Color.trust.opacity(0.3))
                                .frame(width: 2, height: 16)
                                .padding(.leading, 18)
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(LoveMeTheme.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func stepRow(_ step: WorkflowStepInfo, index: Int) -> some View {
        HStack(spacing: LoveMeTheme.sm) {
            // Step number
            Circle()
                .fill(Color.electricBlue.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay {
                    Text("\(index + 1)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.electricBlue)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)

                HStack(spacing: LoveMeTheme.xs) {
                    Text(step.toolName)
                        .font(.timestamp)
                        .foregroundStyle(.trust)
                        .lineLimit(1)

                    if !step.serverName.isEmpty {
                        Text("·")
                            .foregroundStyle(.trust)
                        Text(step.serverName)
                            .font(.timestamp)
                            .foregroundStyle(.trust)
                    }
                }

                // Show input count if any
                if !step.inputs.isEmpty {
                    Text("\(step.inputs.count) input\(step.inputs.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(.sageGreen)
                        .padding(.horizontal, LoveMeTheme.sm)
                        .padding(.vertical, 2)
                        .background(Color.sageGreen.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Spacer()
        }
        .padding(.vertical, LoveMeTheme.xs)
    }

    // MARK: - Executions

    private var executionsSection: some View {
        VStack(alignment: .leading, spacing: LoveMeTheme.md) {
            Text("RECENT RUNS")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)

            if workflowVM.executions.isEmpty {
                HStack(spacing: LoveMeTheme.sm) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(.trust.opacity(0.5))
                    Text("No executions yet")
                        .font(.toolDetail)
                        .foregroundStyle(.trust.opacity(0.7))
                }
                .padding(.vertical, LoveMeTheme.md)
            } else {
                ForEach(workflowVM.executions.prefix(5)) { execution in
                    NavigationLink(value: execution.id) {
                        executionRow(execution)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(LoveMeTheme.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .navigationDestination(for: String.self) { executionId in
            WorkflowExecutionView(executionId: executionId)
        }
    }

    private func executionRow(_ execution: ExecutionItem) -> some View {
        HStack(spacing: LoveMeTheme.sm) {
            Circle()
                .fill(executionColor(execution.status))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(execution.status.capitalized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.textPrimary)

                Text(execution.startedAt, style: .relative)
                    .font(.timestamp)
                    .foregroundStyle(.trust)
                    + Text(" ago")
                    .font(.timestamp)
                    .foregroundStyle(.trust)
            }

            Spacer()

            if let completedAt = execution.completedAt {
                let duration = completedAt.timeIntervalSince(execution.startedAt)
                Text(formatDuration(duration))
                    .font(.toolDetail)
                    .monospacedDigit()
                    .foregroundStyle(.trust)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.trust)
        }
        .padding(.vertical, LoveMeTheme.xs)
    }

    // MARK: - Actions

    private func actionsCard(_ workflow: WorkflowDetail) -> some View {
        Button {
            workflowVM.runWorkflow(id: workflow.id)
        } label: {
            HStack(spacing: LoveMeTheme.sm) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                Text("Run Now")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LoveMeTheme.md)
            .background(Color.heart)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Helpers

    private func executionColor(_ status: String) -> Color {
        switch status {
        case "completed": return .sageGreen
        case "failed": return .softRed
        case "running": return .electricBlue
        case "cancelled": return .amberGlow
        default: return .trust
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return String(format: "%.0fms", interval * 1000)
        } else if interval < 60 {
            return String(format: "%.1fs", interval)
        } else {
            let minutes = Int(interval) / 60
            let seconds = Int(interval) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}
