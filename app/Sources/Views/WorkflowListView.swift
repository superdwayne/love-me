import SwiftUI

struct WorkflowListView: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    @State private var showEditor = false
    @State private var showBuilder = false
    @State private var showDeleteAlert = false
    @State private var workflowToDelete: String?
    @State private var appeared = false

    var body: some View {
        ScrollView {
            if workflowVM.isLoading && workflowVM.workflows.isEmpty {
                skeletonGrid
                    .padding(.horizontal, SolaceTheme.lg)
                    .padding(.top, SolaceTheme.lg)
            } else if workflowVM.workflows.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: SolaceTheme.md) {
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
                    }
                }
                .padding(.horizontal, SolaceTheme.lg)
                .padding(.top, SolaceTheme.md)
                .padding(.bottom, SolaceTheme.xxl)
            }
        }
        .background(.appBackground)
        .navigationTitle("Workflows")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: SolaceTheme.lg) {
                    Button {
                        showBuilder = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.heart)
                    }
                    .accessibilityLabel("Build with AI")

                    Button {
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.heart)
                    }
                    .accessibilityLabel("New workflow")
                }
            }
        }
        .refreshable {
            workflowVM.loadWorkflows()
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                CardWorkflowBuilderView()
            }
        }
        .sheet(isPresented: $showBuilder) {
            NavigationStack {
                WorkflowBuilderWrapperView()
            }
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
        }
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Workflow Card

    private func workflowCard(_ workflow: WorkflowItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: SolaceTheme.md) {
            // Top row: status indicator + name + enabled badge
            HStack(alignment: .top, spacing: SolaceTheme.md) {
                // Status icon with color ring
                ZStack {
                    Circle()
                        .fill(statusColor(workflow.lastRunStatus).opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: statusIcon(workflow.lastRunStatus))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(statusColor(workflow.lastRunStatus))
                }

                VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                    Text(workflow.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !workflow.description.isEmpty {
                        Text(workflow.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.trust)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if !workflow.enabled {
                    Text("OFF")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.trust)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.trust.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // Metadata row: trigger + steps + last run
            HStack(spacing: SolaceTheme.md) {
                triggerBadge(workflow.triggerType)

                // Step count with visual dots
                HStack(spacing: SolaceTheme.xs) {
                    stepDots(count: workflow.stepCount, status: workflow.lastRunStatus)
                    Text("\(workflow.stepCount) step\(workflow.stepCount == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.trust)
                }

                Spacer()

                if let lastRun = workflow.lastRunAt {
                    HStack(spacing: SolaceTheme.xs) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.trust.opacity(0.6))
                        Text(lastRun, style: .relative)
                            .font(.system(size: 11))
                            .foregroundStyle(.trust.opacity(0.7))
                    }
                }
            }

            // Visual step pipeline preview
            if workflow.stepCount > 0 {
                stepPipeline(count: workflow.stepCount, status: workflow.lastRunStatus)
            }
        }
        .padding(SolaceTheme.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    statusColor(workflow.lastRunStatus).opacity(workflow.lastRunStatus == "running" ? 0.3 : 0.08),
                    lineWidth: 1
                )
        )
        .opacity(workflow.enabled ? 1.0 : 0.65)
        .opacity(appeared ? 1.0 : 0.0)
        .offset(y: appeared ? 0 : 12)
        .animation(
            .spring(duration: 0.4, bounce: 0.15).delay(Double(index) * 0.05),
            value: appeared
        )
    }

    // MARK: - Visual Step Pipeline

    private func stepPipeline(count: Int, status: String?) -> some View {
        GeometryReader { geo in
            let maxDots = min(count, 8)
            let dotSize: CGFloat = 6
            let lineHeight: CGFloat = 2
            let totalWidth = geo.size.width
            let spacing = maxDots > 1 ? (totalWidth - CGFloat(maxDots) * dotSize) / CGFloat(maxDots - 1) : 0

            ZStack(alignment: .leading) {
                // Background line
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.trust.opacity(0.12))
                    .frame(height: lineHeight)

                // Active line
                RoundedRectangle(cornerRadius: 1)
                    .fill(pipelineColor(status).opacity(0.4))
                    .frame(width: totalWidth * pipelineFraction(status), height: lineHeight)

                // Dots
                HStack(spacing: spacing) {
                    ForEach(0..<maxDots, id: \.self) { i in
                        Circle()
                            .fill(i == 0 || status == "completed" ? pipelineColor(status) : pipelineColor(status).opacity(0.3))
                            .frame(width: dotSize, height: dotSize)
                    }
                }
            }
        }
        .frame(height: 6)
    }

    private func pipelineColor(_ status: String?) -> Color {
        switch status {
        case "completed": return .sageGreen
        case "failed": return .softRed
        case "running": return .electricBlue
        default: return .trust
        }
    }

    private func pipelineFraction(_ status: String?) -> CGFloat {
        switch status {
        case "completed": return 1.0
        case "failed": return 0.6
        case "running": return 0.5
        default: return 0.0
        }
    }

    // MARK: - Step Dots

    private func stepDots(count: Int, status: String?) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<min(count, 5), id: \.self) { _ in
                Circle()
                    .fill(pipelineColor(status).opacity(0.6))
                    .frame(width: 4, height: 4)
            }
            if count > 5 {
                Text("+\(count - 5)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.trust.opacity(0.6))
            }
        }
    }

    // MARK: - Status Helpers

    private func statusColor(_ status: String?) -> Color {
        switch status {
        case "completed": return .sageGreen
        case "failed": return .softRed
        case "running": return .electricBlue
        default: return .trust
        }
    }

    private func statusIcon(_ status: String?) -> String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "failed": return "exclamationmark.circle.fill"
        case "running": return "arrow.triangle.2.circlepath"
        default: return "bolt.circle.fill"
        }
    }

    private func triggerBadge(_ type: String) -> some View {
        let icon: String
        let color: Color
        switch type {
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

        return HStack(spacing: SolaceTheme.xs) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(type.capitalized)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, SolaceTheme.sm)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: SolaceTheme.xl) {
            Spacer()
                .frame(height: 60)

            // Visual icon cluster
            ZStack {
                Circle()
                    .fill(Color.heart.opacity(0.08))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(Color.heart.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.heart.opacity(0.7))
            }

            VStack(spacing: SolaceTheme.sm) {
                Text("No workflows yet")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.textPrimary)

                Text("Automate tasks with scheduled\nor on-demand workflows.")
                    .font(.system(size: 15))
                    .foregroundStyle(.trust)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: SolaceTheme.md) {
                Button {
                    showBuilder = true
                } label: {
                    HStack(spacing: SolaceTheme.sm) {
                        Image(systemName: "wand.and.stars")
                        Text("Build with AI")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SolaceTheme.xl)
                    .padding(.vertical, SolaceTheme.md)
                    .background(Color.heart)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    showEditor = true
                } label: {
                    HStack(spacing: SolaceTheme.sm) {
                        Image(systemName: "plus")
                        Text("Manual")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.textPrimary)
                    .padding(.horizontal, SolaceTheme.lg)
                    .padding(.vertical, SolaceTheme.md)
                    .background(Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, SolaceTheme.xl)
    }

    // MARK: - Skeleton

    private var skeletonGrid: some View {
        VStack(spacing: SolaceTheme.md) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: SolaceTheme.md) {
                    HStack(spacing: SolaceTheme.md) {
                        Circle()
                            .fill(Color.surfaceElevated)
                            .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.surfaceElevated)
                                .frame(width: 160, height: 16)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.surfaceElevated.opacity(0.6))
                                .frame(width: 100, height: 12)
                        }

                        Spacer()
                    }

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.surfaceElevated.opacity(0.4))
                        .frame(height: 6)
                }
                .padding(SolaceTheme.lg)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .redacted(reason: .placeholder)
            }
        }
    }
}
