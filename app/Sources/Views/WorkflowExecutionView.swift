import SwiftUI

struct WorkflowExecutionView: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    let executionId: String

    @State private var expandedStepId: String?
    @State private var appeared = false

    private var execution: ExecutionItem? {
        workflowVM.currentExecution
    }

    var body: some View {
        ScrollView {
            if let execution {
                VStack(spacing: 0) {
                    executionHeader(execution)
                        .padding(.horizontal, LoveMeTheme.chatHorizontalPadding)
                        .padding(.top, LoveMeTheme.lg)
                        .padding(.bottom, LoveMeTheme.xl)

                    // Steps list
                    LazyVStack(spacing: LoveMeTheme.sm) {
                        ForEach(Array(execution.steps.enumerated()), id: \.element.id) { index, step in
                            stepCard(step, index: index)
                                .padding(.horizontal, LoveMeTheme.chatHorizontalPadding)
                        }
                    }
                    .padding(.bottom, LoveMeTheme.xxl)

                    // Run again button
                    if execution.status == "completed" || execution.status == "failed" || execution.status == "cancelled" {
                        runAgainButton(execution)
                            .padding(.horizontal, LoveMeTheme.chatHorizontalPadding)
                            .padding(.bottom, LoveMeTheme.xxl)
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
            withAnimation(.easeOut(duration: LoveMeTheme.appearDuration)) {
                appeared = true
            }
        }
    }

    // MARK: - Header

    private func executionHeader(_ execution: ExecutionItem) -> some View {
        VStack(spacing: LoveMeTheme.md) {
            // Workflow name and status
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: LoveMeTheme.xs) {
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
            HStack(spacing: LoveMeTheme.lg) {
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
            .padding(.top, LoveMeTheme.xs)

            // Progress bar
            progressBar(execution)
        }
        .padding(LoveMeTheme.lg)
        .background(.surface)
        .clipShape(RoundedRectangle(cornerRadius: LoveMeTheme.sm))
    }

    private func timingLabel(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: LoveMeTheme.xs) {
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
        HStack(spacing: LoveMeTheme.xs) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)

            Text(status.capitalized)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor(status))
        }
        .padding(.horizontal, LoveMeTheme.md)
        .padding(.vertical, LoveMeTheme.sm)
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
                    .animation(.spring(duration: LoveMeTheme.springDuration), value: fraction)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Progress: \(completed) of \(total) steps")
    }

    // MARK: - Step Cards

    private func stepCard(_ step: ExecutionStepItem, index: Int) -> some View {
        let isExpanded = expandedStepId == step.id

        return VStack(spacing: 0) {
            // Header (tap to expand)
            Button {
                withAnimation(.spring(duration: LoveMeTheme.springDuration)) {
                    expandedStepId = isExpanded ? nil : step.id
                }
            } label: {
                stepHeader(step, index: index)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(step.stepName) \(step.status)")
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand") step details")

            // Expanded content
            if isExpanded {
                stepExpandedContent(step)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.surface)
        .clipShape(RoundedRectangle(cornerRadius: LoveMeTheme.sm))
        .overlay(
            HStack {
                Rectangle()
                    .fill(stepBorderColor(step.status))
                    .frame(width: LoveMeTheme.toolCardLeftBorderWidth)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: LoveMeTheme.sm))
        )
    }

    private func stepHeader(_ step: ExecutionStepItem, index: Int) -> some View {
        HStack(spacing: LoveMeTheme.sm) {
            // Step number
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.trust)
                .frame(width: 20, height: 20)
                .background(Color.surfaceElevated)
                .clipShape(Circle())

            // Status icon
            stepStatusIcon(step.status)
                .frame(width: 20, height: 20)

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(step.stepName)
                    .font(.toolTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            // Duration
            if let duration = step.duration {
                Text(String(format: "%.1fs", duration))
                    .font(.toolDetail)
                    .monospacedDigit()
                    .foregroundStyle(.trust)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.trust)
                .rotationEffect(.degrees(isExpanded(step) ? 90 : 0))
                .animation(.spring(duration: LoveMeTheme.springDuration), value: isExpanded(step))
        }
        .padding(.horizontal, LoveMeTheme.md)
        .frame(minHeight: LoveMeTheme.toolCardCollapsedHeight)
    }

    @ViewBuilder
    private func stepStatusIcon(_ status: String) -> some View {
        switch status {
        case "running":
            ProgressView()
                .scaleEffect(0.7)
                .tint(.electricBlue)

        case "success":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.sageGreen)

        case "error":
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.softRed)

        case "skipped":
            Image(systemName: "slash.circle")
                .font(.system(size: 14))
                .foregroundStyle(.trust)

        default: // pending
            Circle()
                .strokeBorder(Color.trust.opacity(0.4), lineWidth: 1.5)
                .frame(width: 14, height: 14)
        }
    }

    private func stepExpandedContent(_ step: ExecutionStepItem) -> some View {
        VStack(alignment: .leading, spacing: LoveMeTheme.sm) {
            Divider()
                .background(.divider)

            // Timing details
            if let startedAt = step.startedAt {
                HStack(spacing: LoveMeTheme.sm) {
                    Text("Started")
                        .font(.timestamp)
                        .foregroundStyle(.trust)
                    Text(startedAt.formatted(date: .omitted, time: .standard))
                        .font(.toolDetail)
                        .foregroundStyle(.textPrimary)
                }
            }

            if let completedAt = step.completedAt {
                HStack(spacing: LoveMeTheme.sm) {
                    Text("Completed")
                        .font(.timestamp)
                        .foregroundStyle(.trust)
                    Text(completedAt.formatted(date: .omitted, time: .standard))
                        .font(.toolDetail)
                        .foregroundStyle(.textPrimary)
                }
            }

            // Output
            if let output = step.output, !output.isEmpty {
                VStack(alignment: .leading, spacing: LoveMeTheme.xs) {
                    Text("OUTPUT")
                        .font(.sectionHeader)
                        .foregroundStyle(.trust)
                        .tracking(1.2)

                    Text(output)
                        .font(.toolDetail)
                        .foregroundStyle(.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(LoveMeTheme.sm)
                        .background(.codeBg)
                        .clipShape(RoundedRectangle(cornerRadius: LoveMeTheme.xs))
                        .lineLimit(10)
                }
            }

            // Error
            if let error = step.error, !error.isEmpty {
                VStack(alignment: .leading, spacing: LoveMeTheme.xs) {
                    Text("ERROR")
                        .font(.sectionHeader)
                        .foregroundStyle(.softRed)
                        .tracking(1.2)

                    Text(error)
                        .font(.toolDetail)
                        .foregroundStyle(.softRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(LoveMeTheme.sm)
                        .background(.codeBg)
                        .clipShape(RoundedRectangle(cornerRadius: LoveMeTheme.xs))
                }
            }
        }
        .padding(.horizontal, LoveMeTheme.md)
        .padding(.bottom, LoveMeTheme.md)
    }

    // MARK: - Run Again

    private func runAgainButton(_ execution: ExecutionItem) -> some View {
        Button {
            workflowVM.runWorkflow(id: execution.workflowId)
        } label: {
            HStack(spacing: LoveMeTheme.sm) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                Text("Run Again")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LoveMeTheme.md)
            .background(.heart)
            .clipShape(RoundedRectangle(cornerRadius: LoveMeTheme.sm))
        }
        .accessibilityLabel("Run this workflow again")
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: LoveMeTheme.lg) {
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

    private func isExpanded(_ step: ExecutionStepItem) -> Bool {
        expandedStepId == step.id
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "completed": return .sageGreen
        case "failed": return .softRed
        case "running": return .electricBlue
        case "cancelled": return .amberGlow
        default: return .trust
        }
    }

    private func stepBorderColor(_ status: String) -> Color {
        switch status {
        case "running": return .electricBlue
        case "success": return .sageGreen
        case "error": return .softRed
        case "skipped": return .trust.opacity(0.4)
        default: return .trust.opacity(0.2)
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
