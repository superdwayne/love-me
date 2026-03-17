import SwiftUI

struct WorkflowDetailView: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    @Environment(\.dismiss) private var dismiss
    let workflowId: String

    @State private var showBuilder = false
    @State private var showDeleteAlert = false
    @State private var appeared = false
    @State private var showInputSheet = false
    @State private var inputValues: [String: String] = [:]
    @State private var expandedDetailStepId: String?
    @State private var showEnhanceSheet = false
    @State private var showEnhanceTestSheet = false
    @State private var showRefineBar = false
    @State private var refinePrompt = ""

    private var workflow: WorkflowDetail? {
        workflowVM.currentWorkflow
    }

    var body: some View {
        ScrollView {
            if let workflow {
                VStack(spacing: SolaceTheme.lg) {
                    heroHeader(workflow)
                    refineSection(workflow)
                    enhanceSection(workflow)
                    enhanceAndTestSection(workflow)
                    stepsTimeline(workflow)
                    executionsSection
                    actionButtons(workflow)
                }
                .padding(.horizontal, SolaceTheme.lg)
                .padding(.top, SolaceTheme.sm)
                .padding(.bottom, SolaceTheme.xxl)
            } else if workflowVM.isLoading {
                VStack(spacing: SolaceTheme.lg) {
                    Spacer().frame(height: 100)
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.textSecondary)
                    Text("Loading workflow...")
                        .font(.chatMessage)
                        .foregroundStyle(.textSecondary)
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
                        showBuilder = true
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
                        .foregroundStyle(.textSecondary)
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
        .sheet(isPresented: $showBuilder, onDismiss: {
            workflowVM.loadWorkflow(id: workflowId)
        }) {
            WorkflowBuilderView(existingWorkflow: workflow)
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
        .sheet(isPresented: $showEnhanceSheet) {
            NavigationStack {
                WorkflowEnhanceSheet(workflowId: workflowId)
            }
        }
        .sheet(isPresented: $showEnhanceTestSheet) {
            NavigationStack {
                EnhanceTestSheet(workflowId: workflowId)
            }
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
                                .foregroundStyle(.textSecondary)
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
                        infoChip(icon: "pause.circle.fill", text: "Paused", color: .textSecondary)
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
                        .foregroundStyle(.textSecondary)
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
                        .foregroundStyle(.textSecondary)
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
                            .foregroundStyle(.textSecondary.opacity(0.3))
                        Text("No executions yet")
                            .font(.system(size: 13))
                            .foregroundStyle(.textSecondary.opacity(0.5))
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
                        .foregroundStyle(.textSecondary)
                    Text("ago")
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary)
                }
            }

            Spacer()

            if let completedAt = execution.completedAt {
                let duration = completedAt.timeIntervalSince(execution.startedAt)
                Text(formatDuration(duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.textSecondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.textSecondary.opacity(0.5))
        }
        .padding(SolaceTheme.md)
        .background(Color.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
    }

    // MARK: - Refine with AI

    private func refineSection(_ workflow: WorkflowDetail) -> some View {
        VStack(spacing: SolaceTheme.sm) {
            if showRefineBar {
                VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                    Text("REFINE WITH AI")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.textSecondary)
                        .tracking(1.2)

                    Text("Describe what to add or change")
                        .font(.system(size: 12))
                        .foregroundStyle(.textSecondary.opacity(0.7))

                    HStack(spacing: SolaceTheme.sm) {
                        TextField("e.g. add a step to render this in Blender", text: $refinePrompt, axis: .vertical)
                            .font(.system(size: 14))
                            .foregroundStyle(.textPrimary)
                            .lineLimit(1...3)
                            .padding(.horizontal, SolaceTheme.md)
                            .padding(.vertical, SolaceTheme.sm)
                            .background(Color.inputBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            guard !refinePrompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            workflowVM.refineWorkflow(workflowId: workflow.id, refinementPrompt: refinePrompt)
                            refinePrompt = ""
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(refinePrompt.trimmingCharacters(in: .whitespaces).isEmpty ? .textSecondary.opacity(0.3) : .electricBlue)
                        }
                        .disabled(refinePrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if workflowVM.isRefining {
                        HStack(spacing: SolaceTheme.sm) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.electricBlue)
                            Text("Refining workflow...")
                                .font(.system(size: 13))
                                .foregroundStyle(.electricBlue)
                        }
                        .padding(.top, SolaceTheme.xs)
                    }

                    if let error = workflowVM.refinementError {
                        HStack(spacing: SolaceTheme.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.softRed)
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.softRed)
                        }
                        .padding(.top, SolaceTheme.xs)
                    }
                }
                .padding(SolaceTheme.md)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: SolaceTheme.cardRadius)
                        .strokeBorder(Color.electricBlue.opacity(0.2), lineWidth: 1)
                )
            } else {
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        showRefineBar = true
                    }
                } label: {
                    HStack(spacing: SolaceTheme.sm) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14))
                        Text("Refine with AI")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.electricBlue)
                    .padding(.horizontal, SolaceTheme.md)
                    .padding(.vertical, SolaceTheme.md)
                    .background(Color.electricBlue.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.cardRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: SolaceTheme.cardRadius)
                            .strokeBorder(Color.electricBlue.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: workflowVM.isRefining) { _, isRefining in
            if !isRefining && workflowVM.refinementError == nil {
                // Reload the workflow after successful refinement
                workflowVM.loadWorkflow(id: workflowId)
                withAnimation(.spring(duration: 0.25)) {
                    showRefineBar = false
                }
            }
        }
    }

    // MARK: - Enhance Section

    private func enhanceSection(_ workflow: WorkflowDetail) -> some View {
        Button {
            showEnhanceSheet = true
            workflowVM.analyzeWorkflow(id: workflow.id)
        } label: {
            HStack(spacing: SolaceTheme.md) {
                ZStack {
                    Circle()
                        .fill(Color.amberGlow.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.amberGlow)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enhance Workflow")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text("Analyze and auto-fix issues")
                        .font(.system(size: 12))
                        .foregroundStyle(.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.textSecondary.opacity(0.5))
            }
            .padding(SolaceTheme.md)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Enhance & Test Section

    private func enhanceAndTestSection(_ workflow: WorkflowDetail) -> some View {
        Button {
            showEnhanceTestSheet = true
            if !workflowVM.isEnhanceTestRunning && workflowVM.enhanceTestResult == nil {
                workflowVM.enhanceAndTest(id: workflow.id)
            }
        } label: {
            HStack(spacing: SolaceTheme.md) {
                ZStack {
                    Circle()
                        .fill(Color.electricBlue.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.electricBlue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enhance & Test")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text("Fix, run, and verify automatically")
                        .font(.system(size: 12))
                        .foregroundStyle(.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.textSecondary.opacity(0.5))
            }
            .padding(SolaceTheme.md)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action Buttons

    private func actionButtons(_ workflow: WorkflowDetail) -> some View {
        VStack(spacing: SolaceTheme.sm) {
            runButton(workflow)
        }
    }

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
        default: return .textSecondary
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
                    .foregroundStyle(.textSecondary)
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
                    .foregroundStyle(.textSecondary)
                }
            }
        }
    }
}

// MARK: - Workflow Enhance Sheet

struct WorkflowEnhanceSheet: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    @Environment(\.dismiss) private var dismiss
    let workflowId: String

    var body: some View {
        ScrollView {
            VStack(spacing: SolaceTheme.lg) {
                if workflowVM.isAnalyzing {
                    loadingState("Analyzing workflow...")
                } else if workflowVM.isEnhancing {
                    loadingState("Enhancing workflow...")
                } else if let enhance = workflowVM.enhanceResult {
                    enhanceResultView(enhance)
                } else if let analysis = workflowVM.analysisResult {
                    analysisView(analysis)
                }
            }
            .padding(.horizontal, SolaceTheme.lg)
            .padding(.top, SolaceTheme.md)
            .padding(.bottom, SolaceTheme.xxl)
        }
        .background(.appBackground)
        .navigationTitle("Enhance Workflow")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    workflowVM.clearAnalysis()
                    dismiss()
                }
                .foregroundStyle(.textSecondary)
            }
        }
    }

    private func loadingState(_ text: String) -> some View {
        VStack(spacing: SolaceTheme.lg) {
            Spacer().frame(height: 60)
            ProgressView()
                .scaleEffect(1.2)
                .tint(.amberGlow)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Analysis View

    private func analysisView(_ analysis: WorkflowAnalysisInfo) -> some View {
        VStack(spacing: SolaceTheme.lg) {
            healthScoreCard(score: analysis.healthScore, health: analysis.overallHealth)

            if !analysis.issues.isEmpty {
                issuesSection(analysis.issues)
            }

            if !analysis.recommendations.isEmpty {
                recommendationsSection(analysis.recommendations)
            }

            if analysis.issues.contains(where: { $0.severity == "critical" || $0.severity == "warning" }) {
                enhanceButton
            } else {
                Text("No fixable issues found — workflow looks healthy!")
                    .font(.system(size: 14))
                    .foregroundStyle(.sageGreen)
                    .frame(maxWidth: .infinity)
                    .padding(SolaceTheme.lg)
                    .background(Color.sageGreen.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Enhance Result View

    private func enhanceResultView(_ result: WorkflowEnhanceInfo) -> some View {
        VStack(spacing: SolaceTheme.lg) {
            healthScoreCard(score: result.healthScore, health: result.overallHealth)

            if result.enhanced {
                // Saved confirmation
                HStack(spacing: SolaceTheme.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.sageGreen)
                    Text("Fixes saved to workflow")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.sageGreen)
                }
                .frame(maxWidth: .infinity)
                .padding(SolaceTheme.md)
                .background(Color.sageGreen.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Fixes list
                VStack(alignment: .leading, spacing: SolaceTheme.md) {
                    HStack(spacing: SolaceTheme.sm) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.sageGreen)
                        Text("\(result.fixCount) FIX\(result.fixCount == 1 ? "" : "ES") APPLIED")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.sageGreen)
                            .tracking(1.0)
                    }

                    ForEach(result.fixesApplied) { fix in
                        HStack(alignment: .top, spacing: SolaceTheme.sm) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.sageGreen)
                                .frame(width: 16)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(fix.description)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.textPrimary)
                                if let step = fix.affectedStep {
                                    Text("Step: \(step)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.textSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(SolaceTheme.lg)
                .background(Color.sageGreen.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Test Run button
                testRunButton
            } else {
                Text("No automatic fixes could be applied.")
                    .font(.system(size: 14))
                    .foregroundStyle(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(SolaceTheme.lg)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !result.issues.isEmpty {
                issuesSection(result.issues)
            }
        }
    }

    // MARK: - Components

    private func healthScoreCard(score: Int, health: String) -> some View {
        VStack(spacing: SolaceTheme.md) {
            ZStack {
                Circle()
                    .stroke(Color.surface, lineWidth: 8)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100.0)
                    .stroke(healthColor(health), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))

                Text("\(score)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(healthColor(health))
            }

            Text(healthLabel(health))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(healthColor(health))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SolaceTheme.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func issuesSection(_ issues: [WorkflowIssueInfo]) -> some View {
        VStack(alignment: .leading, spacing: SolaceTheme.md) {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.amberGlow)
                Text("ISSUES (\(issues.count))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.textSecondary)
                    .tracking(1.0)
            }

            ForEach(issues) { issue in
                HStack(alignment: .top, spacing: SolaceTheme.sm) {
                    Circle()
                        .fill(severityColor(issue.severity))
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: SolaceTheme.xs) {
                            Text(issue.severity.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(severityColor(issue.severity))
                            if let step = issue.affectedStepName {
                                Text("· \(step)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.textSecondary)
                            }
                        }
                        Text(issue.message)
                            .font(.system(size: 13))
                            .foregroundStyle(.textPrimary)
                        if !issue.suggestion.isEmpty {
                            Text(issue.suggestion)
                                .font(.system(size: 12))
                                .foregroundStyle(.textSecondary)
                                .italic()
                        }
                    }
                }
            }
        }
        .padding(SolaceTheme.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func recommendationsSection(_ recs: [WorkflowRecommendation]) -> some View {
        VStack(alignment: .leading, spacing: SolaceTheme.md) {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.electricBlue)
                Text("RECOMMENDATIONS")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.textSecondary)
                    .tracking(1.0)
            }

            ForEach(recs) { rec in
                VStack(alignment: .leading, spacing: 3) {
                    Text(rec.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text(rec.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.textSecondary)
                }
            }
        }
        .padding(SolaceTheme.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var testRunButton: some View {
        Button {
            workflowVM.runWorkflow(id: workflowId)
            workflowVM.clearAnalysis()
            dismiss()
        } label: {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                Text("Test Run")
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
    }

    private var enhanceButton: some View {
        Button {
            workflowVM.enhanceWorkflow(id: workflowId)
        } label: {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14))
                Text("Auto-Fix Issues")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [.amberGlow, .amberGlow.opacity(0.85)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .amberGlow.opacity(0.3), radius: 8, y: 4)
        }
    }

    // MARK: - Helpers

    private func healthColor(_ health: String) -> Color {
        switch health {
        case "excellent": return .sageGreen
        case "good": return .electricBlue
        case "fair": return .amberGlow
        case "poor": return .softRed
        default: return .textSecondary
        }
    }

    private func healthLabel(_ health: String) -> String {
        switch health {
        case "excellent": return "Excellent — Ready to run"
        case "good": return "Good — Minor improvements"
        case "fair": return "Fair — Needs attention"
        case "poor": return "Poor — Critical fixes needed"
        default: return health.capitalized
        }
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "critical": return .softRed
        case "warning": return .amberGlow
        default: return .electricBlue
        }
    }
}

// MARK: - Enhance & Test Sheet

struct EnhanceTestSheet: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    @Environment(\.dismiss) private var dismiss
    let workflowId: String

    var body: some View {
        ScrollView {
            VStack(spacing: SolaceTheme.lg) {
                if let result = workflowVM.enhanceTestResult {
                    resultView(result)
                } else if workflowVM.isEnhanceTestRunning {
                    progressView
                }
            }
            .padding(.horizontal, SolaceTheme.lg)
            .padding(.top, SolaceTheme.md)
            .padding(.bottom, SolaceTheme.xxl)
        }
        .background(.appBackground)
        .navigationTitle("Enhance & Test")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    workflowVM.clearEnhanceTest()
                    dismiss()
                }
                .foregroundStyle(.textSecondary)
            }
        }
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: SolaceTheme.xl) {
            Spacer().frame(height: 40)

            // Phase indicator
            ZStack {
                Circle()
                    .fill(phaseColor.opacity(0.12))
                    .frame(width: 72, height: 72)
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(phaseColor)
            }

            // Phase badge
            Text(phaseBadgeText.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(phaseColor)
                .tracking(1.2)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(phaseColor.opacity(0.1))
                .clipShape(Capsule())

            // Message
            Text(workflowVM.enhanceTestMessage)
                .font(.system(size: 14))
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)

            // Iteration progress
            if workflowVM.enhanceTestMaxIterations > 0 {
                VStack(spacing: SolaceTheme.sm) {
                    HStack {
                        Text("Iteration")
                            .font(.system(size: 12))
                            .foregroundStyle(.textSecondary)
                        Spacer()
                        Text("\(workflowVM.enhanceTestIteration) / \(workflowVM.enhanceTestMaxIterations)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.textPrimary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.surface)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(phaseColor)
                                .frame(
                                    width: geo.size.width * CGFloat(workflowVM.enhanceTestIteration) / CGFloat(max(1, workflowVM.enhanceTestMaxIterations)),
                                    height: 6
                                )
                        }
                    }
                    .frame(height: 6)
                }
                .padding(SolaceTheme.lg)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Cancel button
            Button {
                workflowVM.cancelEnhanceTest(id: workflowId)
            } label: {
                HStack(spacing: SolaceTheme.sm) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.softRed)
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(Color.softRed.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Result View

    private func resultView(_ result: EnhanceTestResultInfo) -> some View {
        VStack(spacing: SolaceTheme.lg) {
            // Convergence hero
            VStack(spacing: SolaceTheme.md) {
                ZStack {
                    Circle()
                        .fill(result.converged ? Color.sageGreen.opacity(0.12) : Color.amberGlow.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: result.converged ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(result.converged ? .sageGreen : .amberGlow)
                }

                Text(result.converged ? "Tests Passing" : "Did Not Converge")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.textPrimary)

                Text(result.converged
                    ? "Workflow passed after \(result.totalIterations) iteration\(result.totalIterations == 1 ? "" : "s")"
                    : "Workflow still failing after \(result.totalIterations) iteration\(result.totalIterations == 1 ? "" : "s")"
                )
                    .font(.system(size: 14))
                    .foregroundStyle(.textSecondary)

                if result.totalFixesApplied > 0 {
                    Text("\(result.totalFixesApplied) fix\(result.totalFixesApplied == 1 ? "" : "es") applied")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.sageGreen)
                        .padding(.horizontal, SolaceTheme.md)
                        .padding(.vertical, SolaceTheme.xs)
                        .background(Color.sageGreen.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SolaceTheme.lg)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Final health score
            VStack(spacing: SolaceTheme.sm) {
                HStack {
                    Text("Final Health Score")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.textSecondary)
                    Spacer()
                    Text("\(result.finalHealthScore)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor(result.finalHealthScore))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.surface)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(scoreColor(result.finalHealthScore))
                            .frame(
                                width: geo.size.width * CGFloat(result.finalHealthScore) / 100.0,
                                height: 8
                            )
                    }
                }
                .frame(height: 8)
            }
            .padding(SolaceTheme.lg)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Iteration timeline
            if !result.iterations.isEmpty {
                VStack(alignment: .leading, spacing: SolaceTheme.md) {
                    HStack(spacing: SolaceTheme.sm) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.electricBlue)
                        Text("ITERATION TIMELINE")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.textSecondary)
                            .tracking(1.0)
                    }

                    ForEach(result.iterations) { iter in
                        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                            HStack(spacing: SolaceTheme.md) {
                                // Status dot
                                Circle()
                                    .fill(iter.executionStatus == "completed" ? Color.sageGreen : Color.softRed)
                                    .frame(width: 10, height: 10)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: SolaceTheme.xs) {
                                        Text("Iteration \(iter.id)")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.textPrimary)
                                        Spacer()
                                        Text(iter.executionStatus == "completed" ? "Passed" : "Failed")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(iter.executionStatus == "completed" ? .sageGreen : .softRed)
                                    }

                                    HStack(spacing: SolaceTheme.md) {
                                        Label("\(iter.issuesFound) found", systemImage: "magnifyingglass")
                                        Label("\(iter.issuesFixed) fixed", systemImage: "wrench.fill")
                                    }
                                    .font(.system(size: 11))
                                    .foregroundStyle(.textSecondary)

                                    if let step = iter.failedStepName {
                                        Text("Failed at: \(step)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.softRed)
                                    }
                                }
                            }

                            // Health score before/after
                            HStack(spacing: SolaceTheme.sm) {
                                Text("Health:")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.textSecondary)
                                Text("\(iter.preFixHealthScore)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(scoreColor(iter.preFixHealthScore))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.textSecondary.opacity(0.5))
                                Text("\(iter.postFixHealthScore)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(scoreColor(iter.postFixHealthScore))
                            }
                            .padding(.leading, 22)

                            // Fix descriptions
                            if !iter.fixDescriptions.isEmpty {
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(iter.fixDescriptions, id: \.self) { desc in
                                        HStack(alignment: .top, spacing: SolaceTheme.xs) {
                                            Image(systemName: "wrench.and.screwdriver.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.sageGreen)
                                                .padding(.top, 2)
                                            Text(desc)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.textSecondary)
                                        }
                                    }
                                }
                                .padding(.leading, 22)
                            }
                        }
                        .padding(SolaceTheme.md)
                        .background(Color.surfaceElevated.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(SolaceTheme.lg)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Helpers

    private var phaseColor: Color {
        switch workflowVM.enhanceTestPhase {
        case "analyzing": return .electricBlue
        case "enhancing": return .amberGlow
        case "testing": return .heart
        case "retrying": return .softRed
        case "converged": return .sageGreen
        default: return .textSecondary
        }
    }

    private var phaseBadgeText: String {
        switch workflowVM.enhanceTestPhase {
        case "analyzing": return "Analyzing"
        case "enhancing": return "Enhancing"
        case "testing": return "Testing"
        case "retrying": return "Retrying"
        case "converged": return "Converged"
        case "cancelled": return "Cancelled"
        default: return "Starting"
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 { return .sageGreen }
        if score >= 70 { return .electricBlue }
        if score >= 50 { return .amberGlow }
        return .softRed
    }
}
