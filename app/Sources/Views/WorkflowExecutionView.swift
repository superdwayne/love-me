import SwiftUI

struct WorkflowExecutionView: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    let executionId: String

    @State private var expandedStepId: String?
    @State private var appeared = false
    @State private var liveTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var timerTick: Int = 0

    private var execution: ExecutionItem? {
        workflowVM.currentExecution
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                if let execution {
                    VStack(spacing: 0) {
                        executionHeader(execution)
                            .padding(.horizontal, SolaceTheme.chatHorizontalPadding)
                            .padding(.top, SolaceTheme.lg)
                            .padding(.bottom, SolaceTheme.xl)

                        // Steps list with animated connectors
                        LazyVStack(spacing: 0) {
                            ForEach(Array(execution.steps.enumerated()), id: \.element.id) { index, step in
                                WorkflowStepCard(
                                    mode: .execution,
                                    index: index,
                                    name: step.stepName,
                                    toolName: step.stepName,
                                    serverName: "",
                                    status: step.status,
                                    output: step.output,
                                    error: step.error,
                                    startedAt: step.startedAt,
                                    completedAt: step.completedAt,
                                    isExpanded: expandedStepId == step.id,
                                    onToggleExpand: {
                                        withAnimation(.spring(duration: SolaceTheme.springDuration)) {
                                            expandedStepId = expandedStepId == step.id ? nil : step.id
                                        }
                                    }
                                )
                                .id(step.id)
                                .padding(.horizontal, SolaceTheme.chatHorizontalPadding)
                                .padding(.bottom, SolaceTheme.xs)

                                // Animated connector
                                if index < execution.steps.count - 1 {
                                    HStack {
                                        Rectangle()
                                            .fill(connectorColor(for: step.status))
                                            .frame(width: 2, height: 16)
                                            .padding(.leading, 28)
                                            .animation(.easeInOut(duration: 0.3), value: step.status)
                                        Spacer()
                                    }
                                    .padding(.horizontal, SolaceTheme.chatHorizontalPadding)
                                }
                            }
                        }
                        .padding(.bottom, SolaceTheme.xxl)

                        // Cancel button (while running)
                        if execution.status == "running" {
                            cancelButton(execution)
                                .padding(.horizontal, SolaceTheme.chatHorizontalPadding)
                                .padding(.bottom, SolaceTheme.md)
                        }

                        // Run again button
                        if execution.status == "completed" || execution.status == "failed" || execution.status == "cancelled" {
                            runAgainButton(execution)
                                .padding(.horizontal, SolaceTheme.chatHorizontalPadding)
                                .padding(.bottom, SolaceTheme.xxl)
                        }
                    }
                } else if workflowVM.isLoading {
                    loadingState
                }
            }
            .background(.appBackground)
            .navigationTitle("Execution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .opacity(appeared ? 1.0 : 0.0)
            .onAppear {
                workflowVM.loadExecution(id: executionId)
                withAnimation(.easeOut(duration: SolaceTheme.appearDuration)) {
                    appeared = true
                }
            }
            .onChange(of: runningStepId) { _, newId in
                if let newId {
                    withAnimation(.easeOut(duration: 0.3)) {
                        scrollProxy.scrollTo(newId, anchor: .center)
                    }
                    HapticManager.stepStarted()
                }
            }
            .onChange(of: completedStepCount) { oldCount, newCount in
                if newCount > oldCount {
                    HapticManager.stepCompleted()
                }
            }
            .onChange(of: execution?.status) { _, newStatus in
                if newStatus == "completed" || newStatus == "failed" {
                    HapticManager.workflowCompleted()
                }
            }
            .onReceive(liveTimer) { _ in
                if execution?.status == "running" {
                    timerTick += 1
                }
            }
        }
    }

    private var runningStepId: String? {
        execution?.steps.first(where: { $0.status == "running" })?.id
    }

    private var completedStepCount: Int {
        execution?.steps.filter { $0.status == "success" || $0.status == "error" }.count ?? 0
    }

    private func connectorColor(for status: String) -> Color {
        switch status {
        case "success": return .sageGreen
        case "running": return .electricBlue
        case "error": return .softRed
        default: return .trust.opacity(0.2)
        }
    }

    // MARK: - Header

    private func executionHeader(_ execution: ExecutionItem) -> some View {
        VStack(spacing: SolaceTheme.md) {
            // Workflow name and status
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                    Text(execution.workflowName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.textPrimary)

                    if !execution.triggerInfo.isEmpty {
                        Text("Triggered: \(execution.triggerInfo)")
                            .font(.toolDetail)
                            .foregroundStyle(.trust)
                    }
                }

                Spacer()

                statusBadge(execution.status)
            }

            // Timing row
            HStack(spacing: SolaceTheme.lg) {
                timingLabel(
                    icon: "play.circle",
                    label: "Started",
                    value: execution.startedAt.formatted(date: .omitted, time: .standard)
                )

                if let completedAt = execution.completedAt {
                    timingLabel(
                        icon: "stop.circle",
                        label: "Ended",
                        value: completedAt.formatted(date: .omitted, time: .standard)
                    )
                }

                if let duration = executionDuration(execution) {
                    timingLabel(
                        icon: "timer",
                        label: "Duration",
                        value: formatDuration(duration)
                    )
                }

                Spacer()
            }
            .padding(.top, SolaceTheme.xs)

            // Progress bar
            progressBar(execution)
        }
        .padding(SolaceTheme.lg)
        .background(.surface)
        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
    }

    private func timingLabel(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: SolaceTheme.xs) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.trust)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.trust)
                    .tracking(0.8)
            }
            Text(value)
                .font(.toolDetail)
                .monospacedDigit()
                .foregroundStyle(.textPrimary)
        }
    }

    private func statusBadge(_ status: String) -> some View {
        HStack(spacing: SolaceTheme.xs) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)

            Text(status.capitalized)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor(status))
        }
        .padding(.horizontal, SolaceTheme.md)
        .padding(.vertical, SolaceTheme.sm)
        .background(statusColor(status).opacity(0.12))
        .clipShape(Capsule())
    }

    private func progressBar(_ execution: ExecutionItem) -> some View {
        let total = execution.steps.count
        let completed = execution.steps.filter { $0.status == "success" || $0.status == "error" || $0.status == "skipped" }.count
        let fraction = total > 0 ? Double(completed) / Double(total) : 0

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.surfaceElevated)
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(execution.status == "failed" ? Color.softRed : Color.sageGreen)
                    .frame(width: geo.size.width * fraction, height: 6)
                    .animation(.spring(duration: SolaceTheme.springDuration), value: fraction)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Progress: \(completed) of \(total) steps")
    }

    // MARK: - Cancel

    @State private var showCancelConfirmation = false

    private func cancelButton(_ execution: ExecutionItem) -> some View {
        Button {
            showCancelConfirmation = true
        } label: {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14))
                Text("Stop Execution")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.softRed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SolaceTheme.md)
            .background(.softRed.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
        }
        .accessibilityLabel("Stop this workflow execution")
        .alert("Stop Execution?", isPresented: $showCancelConfirmation) {
            Button("Stop", role: .destructive) {
                workflowVM.cancelExecution(id: execution.id)
            }
            Button("Continue Running", role: .cancel) {}
        } message: {
            Text("This will cancel the current execution. Any completed steps will keep their results.")
        }
    }

    // MARK: - Run Again

    private func runAgainButton(_ execution: ExecutionItem) -> some View {
        Button {
            workflowVM.runWorkflow(id: execution.workflowId)
        } label: {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                Text("Run Again")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SolaceTheme.md)
            .background(.heart)
            .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
        }
        .accessibilityLabel("Run this workflow again")
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: SolaceTheme.lg) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
                .tint(.trust)
            Text("Loading execution...")
                .font(.chatMessage)
                .foregroundStyle(.trust)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "completed": return .sageGreen
        case "failed": return .softRed
        case "running": return .electricBlue
        case "cancelled": return .amberGlow
        default: return .trust
        }
    }

    private func executionDuration(_ execution: ExecutionItem) -> TimeInterval? {
        guard let completedAt = execution.completedAt else {
            // Still running - show elapsed time
            return Date().timeIntervalSince(execution.startedAt)
        }
        return completedAt.timeIntervalSince(execution.startedAt)
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
