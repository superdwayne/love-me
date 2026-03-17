import SwiftUI

struct WorkflowListView: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    @State private var showBuilder = false
    @State private var showDeleteAlert = false
    @State private var workflowToDelete: String?
    @State private var appeared = false
    @State private var runningPulse = false

    private var activeCount: Int {
        workflowVM.workflows.filter { $0.enabled }.count
    }

    private var runningCount: Int {
        workflowVM.workflows.filter { $0.lastRunStatus == "running" }.count
    }

    var body: some View {
        ScrollView {
            if workflowVM.isLoading && workflowVM.workflows.isEmpty {
                skeletonGrid
                    .padding(.horizontal, 16)
                    .padding(.top, SolaceTheme.lg)
            } else if workflowVM.workflows.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    statsBar
                        .padding(.horizontal, 16)
                        .padding(.top, SolaceTheme.md)
                        .padding(.bottom, SolaceTheme.lg)

                    ForEach(Array(workflowVM.workflows.enumerated()), id: \.element.id) { index, workflow in
                        NavigationLink(value: workflow.id) {
                            workflowCard(workflow, index: index)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                workflowVM.runWorkflow(id: workflow.id)
                            } label: {
                                Label("Run Now", systemImage: "play.fill")
                            }

                            Button(role: .destructive) {
                                workflowToDelete = workflow.id
                                showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, SolaceTheme.md)
                    }
                }
                .padding(.bottom, SolaceTheme.xxl)
            }
        }
        .background(.appBackground)
        .navigationTitle("Workflows")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showBuilder = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.heart)
                }
                .accessibilityLabel("New workflow")
            }
        }
        .refreshable {
            workflowVM.loadWorkflows()
        }
        .sheet(isPresented: $showBuilder) {
            WorkflowBuilderView()
        }
        .alert("Delete Workflow", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let id = workflowToDelete {
                    workflowVM.deleteWorkflow(id: id)
                }
            }
        } message: {
            Text("Are you sure you want to delete this workflow? This cannot be undone.")
        }
        .navigationDestination(for: String.self) { workflowId in
            WorkflowDetailView(workflowId: workflowId)
        }
        .onAppear {
            workflowVM.loadWorkflows()
            withAnimation(.easeOut(duration: SolaceTheme.appearDuration)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                runningPulse = true
            }
        }
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 0) {
            statCell(
                value: "\(workflowVM.workflows.count)",
                label: "Total",
                color: .textSecondary
            )

            Divider()
                .frame(height: 28)
                .foregroundStyle(.divider)

            statCell(
                value: "\(activeCount)",
                label: "Active",
                color: .sageGreen
            )

            Divider()
                .frame(height: 28)
                .foregroundStyle(.divider)

            if runningCount > 0 {
                statCell(
                    value: "\(runningCount)",
                    label: "Running",
                    color: .electricBlue
                )
            } else {
                statCell(
                    value: "0",
                    label: "Running",
                    color: .textSecondary.opacity(0.4)
                )
            }
        }
        .padding(.vertical, SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.cardRadius))
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.textSecondary.opacity(0.6))
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Workflow Card

    private func workflowCard(_ workflow: WorkflowItem, index: Int) -> some View {
        HStack(spacing: SolaceTheme.md) {
            triggerIcon(workflow)

            VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                HStack(alignment: .firstTextBaseline, spacing: SolaceTheme.sm) {
                    Text(workflow.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    statusBadge(workflow.lastRunStatus)
                }

                if !workflow.description.isEmpty {
                    Text(workflow.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: SolaceTheme.sm) {
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 9))
                        Text("\(workflow.stepCount)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.textSecondary.opacity(0.7))

                    Text("·")
                        .foregroundStyle(.textSecondary.opacity(0.3))

                    scheduleLabel(workflow)

                    Spacer(minLength: 0)

                    if let lastRun = workflow.lastRunAt {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(statusColor(workflow.lastRunStatus).opacity(0.5))
                                .frame(width: 4, height: 4)
                            Text(lastRun, style: .relative)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.textSecondary.opacity(0.5))
                        }
                    }
                }
            }
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SolaceTheme.cardRadius)
                .strokeBorder(
                    workflow.lastRunStatus == "running"
                        ? Color.electricBlue.opacity(runningPulse ? 0.3 : 0.1)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .opacity(workflow.enabled ? 1.0 : 0.45)
        .opacity(appeared ? 1.0 : 0.0)
        .offset(y: appeared ? 0 : 10)
        .animation(
            .spring(duration: 0.4, bounce: 0.12).delay(Double(index) * 0.04),
            value: appeared
        )
    }

    // MARK: - Trigger Icon

    private func triggerIcon(_ workflow: WorkflowItem) -> some View {
        let icon: String
        let color: Color
        switch workflow.triggerType {
        case "cron":
            icon = "clock.fill"
            color = .electricBlue
        case "manual":
            icon = "hand.tap.fill"
            color = .sageGreen
        default:
            icon = "bolt.fill"
            color = .amberGlow
        }

        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.12))
                .frame(width: 40, height: 40)

            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
        }
        .overlay(alignment: .topTrailing) {
            if workflow.lastRunStatus == "running" {
                Circle()
                    .fill(Color.electricBlue)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .fill(Color.electricBlue.opacity(runningPulse ? 0.0 : 0.6))
                            .frame(width: runningPulse ? 16 : 8, height: runningPulse ? 16 : 8)
                    )
                    .offset(x: 2, y: -2)
            }
        }
    }

    // MARK: - Schedule Label

    private func scheduleLabel(_ workflow: WorkflowItem) -> some View {
        Group {
            if workflow.triggerType == "cron" && !workflow.triggerDetail.isEmpty {
                Text(workflow.triggerDetail)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.electricBlue.opacity(0.7))
            } else if workflow.triggerType == "manual" {
                Text("Manual")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.sageGreen.opacity(0.7))
            } else {
                Text(workflow.triggerType.capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.amberGlow.opacity(0.7))
            }
        }
    }

    // MARK: - Status Badge

    private func statusBadge(_ status: String?) -> some View {
        let color = statusColor(status)
        let label = statusLabel(status)
        let icon = statusIcon(status)

        return HStack(spacing: 3) {
            if status == "running" {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                    .symbolEffect(.pulse, options: .repeating)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.3)
        }
        .foregroundStyle(color)
        .padding(.horizontal, SolaceTheme.sm)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Status Helpers

    private func statusColor(_ status: String?) -> Color {
        switch status {
        case "completed": return .sageGreen
        case "failed": return .softRed
        case "running": return .electricBlue
        default: return .textSecondary.opacity(0.5)
        }
    }

    private func statusIcon(_ status: String?) -> String {
        switch status {
        case "completed": return "checkmark"
        case "failed": return "xmark"
        case "running": return "arrow.triangle.2.circlepath"
        default: return "circle"
        }
    }

    private func statusLabel(_ status: String?) -> String {
        switch status {
        case "completed": return "Done"
        case "failed": return "Failed"
        case "running": return "Running"
        default: return "Idle"
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 80)

            VStack(spacing: SolaceTheme.xl) {
                // Orchestration icon cluster
                ZStack {
                    Circle()
                        .fill(Color.coral.opacity(0.06))
                        .frame(width: 100, height: 100)

                    Circle()
                        .fill(Color.coral.opacity(0.1))
                        .frame(width: 64, height: 64)

                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.coral)
                }

                VStack(spacing: SolaceTheme.sm) {
                    Text("Automate your work")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.textPrimary)

                    Text("Create workflows that run tools on a\nschedule or on demand. Your AI, working\nwhile you're away.")
                        .font(.system(size: 14))
                        .foregroundStyle(.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                Button {
                    showBuilder = true
                } label: {
                    HStack(spacing: SolaceTheme.sm) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14))
                        Text("Create Workflow")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: 260)
                    .padding(.vertical, 13)
                    .background(Color.coral)
                    .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.cardRadius))
                }
                .padding(.top, SolaceTheme.sm)

                // Hint cards
                VStack(spacing: SolaceTheme.sm) {
                    hintCard(
                        icon: "clock.fill",
                        color: .electricBlue,
                        text: "Schedule daily reports, backups, or checks"
                    )
                    hintCard(
                        icon: "hand.tap.fill",
                        color: .sageGreen,
                        text: "Run complex multi-step tasks on demand"
                    )
                    hintCard(
                        icon: "bolt.fill",
                        color: .amberGlow,
                        text: "Chain MCP tools into powerful pipelines"
                    )
                }
                .padding(.horizontal, 32)
                .padding(.top, SolaceTheme.md)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, SolaceTheme.xl)
    }

    private func hintCard(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: SolaceTheme.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.1))
                    .frame(width: 28, height: 28)

                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
            }

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SolaceTheme.md)
        .padding(.vertical, SolaceTheme.sm)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Skeleton

    private var skeletonGrid: some View {
        VStack(spacing: SolaceTheme.md) {
            // Stats bar skeleton
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.surfaceElevated)
                            .frame(width: 24, height: 18)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.surfaceElevated.opacity(0.5))
                            .frame(width: 40, height: 10)
                    }
                    .frame(maxWidth: .infinity)
                    if i < 2 {
                        Divider()
                            .frame(height: 28)
                            .foregroundStyle(.divider)
                    }
                }
            }
            .padding(.vertical, SolaceTheme.md)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.cardRadius))

            // Card skeletons
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: SolaceTheme.md) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.surfaceElevated)
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                        HStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.surfaceElevated)
                                .frame(width: 140, height: 14)
                            Spacer()
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.surfaceElevated.opacity(0.5))
                                .frame(width: 44, height: 16)
                        }

                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.surfaceElevated.opacity(0.6))
                            .frame(width: 200, height: 12)

                        HStack(spacing: SolaceTheme.sm) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.surfaceElevated.opacity(0.4))
                                .frame(width: 30, height: 10)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.surfaceElevated.opacity(0.4))
                                .frame(width: 60, height: 10)
                            Spacer()
                        }
                    }
                }
                .padding(SolaceTheme.md)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.cardRadius))
            }
        }
        .redacted(reason: .placeholder)
    }
}
