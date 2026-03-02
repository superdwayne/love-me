import SwiftUI

struct WorkflowListView: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    @State private var showEditor = false
    @State private var showBuilder = false
    @State private var showDeleteAlert = false
    @State private var workflowToDelete: String?

    var body: some View {
        List {
            if workflowVM.isLoading && workflowVM.workflows.isEmpty {
                ForEach(0..<4, id: \.self) { _ in
                    skeletonRow
                }
                .listRowBackground(Color.surface)
            } else if workflowVM.workflows.isEmpty {
                emptyState
                    .listRowBackground(Color.appBackground)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(workflowVM.workflows) { workflow in
                    NavigationLink(value: workflow.id) {
                        workflowRow(workflow)
                    }
                    .listRowBackground(Color.surface)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            workflowToDelete = workflow.id
                            showDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
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
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
                WorkflowEditorView(existingWorkflow: nil)
            }
        }
        .sheet(isPresented: $showBuilder) {
            NavigationStack {
                WorkflowBuilderView()
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
        }
    }

    // MARK: - Subviews

    private func workflowRow(_ workflow: WorkflowItem) -> some View {
        HStack(spacing: SolaceTheme.md) {
            // Status dot
            statusDot(for: workflow.lastRunStatus)

            VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                HStack(spacing: SolaceTheme.sm) {
                    Text(workflow.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)

                    if !workflow.enabled {
                        Text("OFF")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.trust)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.trust.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: SolaceTheme.sm) {
                    triggerBadge(workflow.triggerType)

                    if !workflow.triggerDetail.isEmpty {
                        Text(workflow.triggerDetail)
                            .font(.timestamp)
                            .foregroundStyle(.trust)
                            .lineLimit(1)
                    }

                    if let lastRun = workflow.lastRunAt {
                        Text("· \(lastRun, style: .relative) ago")
                            .font(.timestamp)
                            .foregroundStyle(.trust)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.trust)
        }
        .padding(.vertical, SolaceTheme.xs)
        .accessibilityLabel("\(workflow.name), \(workflow.triggerType) trigger, \(workflow.enabled ? "enabled" : "disabled")")
    }

    private func statusDot(for status: String?) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 10, height: 10)
    }

    private func statusColor(_ status: String?) -> Color {
        switch status {
        case "completed": return .sageGreen
        case "failed": return .softRed
        case "running": return .amberGlow
        default: return .trust.opacity(0.4)
        }
    }

    private func triggerBadge(_ type: String) -> some View {
        Text(type.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(type == "cron" ? .electricBlue : .amberGlow)
            .padding(.horizontal, SolaceTheme.sm)
            .padding(.vertical, 2)
            .background(
                (type == "cron" ? Color.electricBlue : Color.amberGlow).opacity(0.15)
            )
            .clipShape(Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: SolaceTheme.md) {
            Spacer()
                .frame(height: 80)

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(.trust.opacity(0.5))

            Text("No workflows yet")
                .font(.displaySubtitle)
                .foregroundStyle(.textPrimary)

            Text("Automate tasks with scheduled or on-demand workflows.")
                .font(.chatMessage)
                .foregroundStyle(.trust)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SolaceTheme.xxl)

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
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.top, SolaceTheme.sm)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var skeletonRow: some View {
        HStack(spacing: SolaceTheme.md) {
            Circle()
                .fill(Color.surfaceElevated)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.surfaceElevated)
                    .frame(width: 160, height: 16)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.surfaceElevated.opacity(0.6))
                    .frame(width: 80, height: 12)
            }

            Spacer()
        }
        .padding(.vertical, SolaceTheme.xs)
        .redacted(reason: .placeholder)
    }
}
