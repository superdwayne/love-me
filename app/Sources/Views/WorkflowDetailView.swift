import SwiftUI

struct WorkflowDetailView: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    @Environment(\.dismiss) private var dismiss
    let workflowId: String

    @State private var showEditor = false
    @State private var showDeleteAlert = false
    @State private var appeared = false
    @State private var showInputSheet = false
    @State private var inputValues: [String: String] = [:]
    @State private var expandedDetailStepId: String?

    private var workflow: WorkflowDetail? {
        workflowVM.currentWorkflow
    }

    var body: some View {
        ScrollView {
            if let workflow {
                VStack(spacing: SolaceTheme.lg) {
                    heroHeader(workflow)
                    stepsTimeline(workflow)
                    executionsSection
                    runButton(workflow)
                }
                .padding(.horizontal, SolaceTheme.lg)
                .padding(.top, SolaceTheme.sm)
                .padding(.bottom, SolaceTheme.xxl)
            } else if workflowVM.isLoading {
                VStack(spacing: SolaceTheme.lg) {
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
            withAnimation(.easeOut(duration: SolaceTheme.appearDuration)) {
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

    // MARK: - Hero Header

    private func heroHeader(_ workflow: WorkflowDetail) -> some View {
        VStack(spacing: 0) {
            // Gradient accent bar
            LinearGradient(
                colors: [.heart.opacity(0.6), .electricBlue.opacity(0.4)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 4)
            .clipShape(RoundedRectangle(cornerRadius: 2))

            VStack(alignment: .leading, spacing: SolaceTheme.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                        Text(workflow.name)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.textPrimary)

                        if !workflow.description.isEmpty {
                            Text(workflow.description)
                                .font(.system(size: 14))
                                .foregroundStyle(.trust)
                                .lineLimit(3)
                        }
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { workflow.enabled },
                        set: { _ in
                            workflowVM.toggleWorkflowEnabled(id: workflow.id)
                        }
                    ))
                    .labelsHidden()
                    .tint(.heart)
                }

                // Info chips row
                HStack(spacing: SolaceTheme.sm) {
                    infoChip(
                        icon: triggerIcon(workflow.trigger.type),
                        text: triggerLabel(workflow),
                        color: triggerColor(workflow.trigger.type)
                    )

                    infoChip(
                        icon: "square.stack.3d.up.fill",
                        text: "\(workflow.steps.count) step\(workflow.steps.count == 1 ? "" : "s")",
                        color: .electricBlue
                    )

                    if !workflow.enabled {
                        infoChip(icon: "pause.circle.fill", text: "Paused", color: .trust)
                    }
                }
            }
            .padding(SolaceTheme.lg)
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func infoChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: SolaceTheme.xs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, SolaceTheme.sm)
        .padding(.vertical, SolaceTheme.xs)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private func triggerIcon(_ type: String) -> String {
        switch type {
        case "cron": return "clock.fill"
        case "manual": return "hand.tap.fill"
        default: return "bolt.fill"
        }
    }

    private func triggerColor(_ type: String) -> Color {
        switch type {
        case "cron": return .electricBlue
        case "manual": return .sageGreen
        default: return .amberGlow
        }
    }

    private func triggerLabel(_ workflow: WorkflowDetail) -> String {
        if workflow.trigger.type == "manual" {
            if let params = workflow.trigger.inputParams, !params.isEmpty {
                return "Manual · \(params.count) input\(params.count == 1 ? "" : "s")"
            }
            return "Manual"
        }
        if let cron = workflow.trigger.cronExpression, !cron.isEmpty {
            return cron
        }
        return workflow.trigger.type.capitalized
    }

    // MARK: - Steps Timeline

    private func stepsTimeline(_ workflow: WorkflowDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                HStack(spacing: SolaceTheme.sm) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.electricBlue)
                    Text("PIPELINE")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.trust)
                        .tracking(1.2)
                }

                Spacer()

                Text("\(workflow.steps.count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.electricBlue)
                    .padding(.horizontal, SolaceTheme.sm)
                    .padding(.vertical, 3)
                    .background(Color.electricBlue.opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, SolaceTheme.lg)
            .padding(.top, SolaceTheme.lg)
            .padding(.bottom, SolaceTheme.md)

            // Steps with visual connectors
            VStack(spacing: 0) {
                ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                    WorkflowStepCard(
                        mode: .readOnly,
                        index: index,
                        name: step.name,
                        toolName: step.toolName,
                        serverName: step.serverName,
                        inputs: step.inputs,
                        isExpanded: expandedDetailStepId == step.id,
                        onToggleExpand: {
                            withAnimation(.spring(duration: SolaceTheme.springDuration)) {
                                expandedDetailStepId = expandedDetailStepId == step.id ? nil : step.id
                            }
                        }
                    )

                    if index < workflow.steps.count - 1 {
                        // Flow connector
                        HStack(spacing: 0) {
                            Spacer().frame(width: 18)
                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.electricBlue.opacity(0.4), .electricBlue.opacity(0.15)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 2, height: 12)

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.electricBlue.opacity(0.3))

                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.electricBlue.opacity(0.15), .electricBlue.opacity(0.4)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 2, height: 4)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, SolaceTheme.md)
            .padding(.bottom, SolaceTheme.lg)
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Executions

    private var executionsSection: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.md) {
            HStack {
                HStack(spacing: SolaceTheme.sm) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.sageGreen)
                    Text("RECENT RUNS")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.trust)
                        .tracking(1.2)
                }

                Spacer()

                if !workflowVM.executions.isEmpty {
                    Text("\(workflowVM.executions.count)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.sageGreen)
                        .padding(.horizontal, SolaceTheme.sm)
                        .padding(.vertical, 3)
                        .background(Color.sageGreen.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            if workflowVM.executions.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: SolaceTheme.sm) {
                        Image(systemName: "tray")
                            .font(.system(size: 24))
                            .foregroundStyle(.trust.opacity(0.3))
                        Text("No executions yet")
                            .font(.system(size: 13))
                            .foregroundStyle(.trust.opacity(0.5))
                    }
                    .padding(.vertical, SolaceTheme.xl)
                    Spacer()
                }
            } else {
                VStack(spacing: SolaceTheme.sm) {
                    ForEach(workflowVM.executions.prefix(5)) { execution in
                        NavigationLink(value: execution.id) {
                            executionCard(execution)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(SolaceTheme.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .navigationDestination(for: String.self) { executionId in
            WorkflowExecutionView(executionId: executionId)
        }
    }

    private func executionCard(_ execution: ExecutionItem) -> some View {
        HStack(spacing: SolaceTheme.md) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(executionColor(execution.status).opacity(0.12))
                    .frame(width: 32, height: 32)

                Image(systemName: executionIcon(execution.status))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(executionColor(execution.status))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(execution.status.capitalized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.textPrimary)

                HStack(spacing: SolaceTheme.xs) {
                    Text(execution.startedAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(.trust)
                    Text("ago")
                        .font(.system(size: 11))
                        .foregroundStyle(.trust)
                }
            }

            Spacer()

            if let completedAt = execution.completedAt {
                let duration = completedAt.timeIntervalSince(execution.startedAt)
                Text(formatDuration(duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.trust)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.trust.opacity(0.5))
        }
        .padding(SolaceTheme.md)
        .background(Color.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
    }

    // MARK: - Run Button

    private func runButton(_ workflow: WorkflowDetail) -> some View {
        Button {
            if let params = workflow.trigger.inputParams, !params.isEmpty {
                inputValues = Dictionary(uniqueKeysWithValues: params.map { ($0.name, "") })
                showInputSheet = true
            } else {
                workflowVM.runWorkflow(id: workflow.id)
            }
        } label: {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                Text("Run Now")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [.heart, .heart.opacity(0.85)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .heart.opacity(0.3), radius: 8, y: 4)
        }
        .sheet(isPresented: $showInputSheet) {
            if let params = workflow.trigger.inputParams {
                WorkflowInputSheet(
                    workflowName: workflow.name,
                    params: params,
                    values: $inputValues
                ) {
                    workflowVM.runWorkflow(id: workflow.id, inputParams: inputValues)
                    showInputSheet = false
                }
            }
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

    private func executionIcon(_ status: String) -> String {
        switch status {
        case "completed": return "checkmark"
        case "failed": return "xmark"
        case "running": return "arrow.triangle.2.circlepath"
        case "cancelled": return "stop.fill"
        default: return "clock"
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

// MARK: - Input Sheet for Manual Workflows

struct WorkflowInputSheet: View {
    let workflowName: String
    let params: [InputParamInfo]
    @Binding var values: [String: String]
    let onRun: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: SolaceTheme.lg) {
                Text("Provide inputs to run this workflow.")
                    .font(.chatMessage)
                    .foregroundStyle(.trust)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SolaceTheme.lg)

                VStack(spacing: SolaceTheme.md) {
                    ForEach(params, id: \.name) { param in
                        VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                            Text(param.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.textPrimary)

                            TextField(
                                param.placeholder ?? param.name,
                                text: Binding(
                                    get: { values[param.name] ?? "" },
                                    set: { values[param.name] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        }
                    }
                }
                .padding(.horizontal, SolaceTheme.lg)

                Spacer()

                Button {
                    onRun()
                } label: {
                    HStack(spacing: SolaceTheme.sm) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                        Text("Run")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SolaceTheme.md)
                    .background(Color.heart)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, SolaceTheme.lg)
                .padding(.bottom, SolaceTheme.lg)
            }
            .background(.appBackground)
            .navigationTitle(workflowName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.trust)
                }
            }
        }
    }
}
