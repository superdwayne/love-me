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
                    workflowRow(workflow)
                        .listRowBackground(Color.surface)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            workflowVM.loadWorkflow(id: workflow.id)
                        }
                        .swipeActions(edge: .trailing) {
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
                HStack(spacing: LoveMeTheme.lg) {
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
        .onAppear {
            workflowVM.loadWorkflows()
        }
    }

    // MARK: - Subviews

    private func workflowRow(_ workflow: WorkflowItem) -> some View {
        HStack(spacing: LoveMeTheme.md) {
            // Status dot
            statusDot(for: workflow.lastRunStatus)

            VStack(alignment: .leading, spacing: LoveMeTheme.xs) {
                Text(workflow.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)

                HStack(spacing: LoveMeTheme.sm) {
                    triggerBadge(workflow.triggerType)

                    if let lastRun = workflow.lastRunAt {
                        Text(lastRun, style: .relative)
                            .font(.timestamp)
                            .foregroundStyle(.trust)
                    }
                }
            }

            Spacer()

            // Enabled toggle
            Toggle("", isOn: Binding(
                get: { workflow.enabled },
                set: { _ in
                    // Toggle enabled state via ViewModel
                    if var detail = workflowVM.currentWorkflow, detail.id == workflow.id {
                        detail = WorkflowDetail(
                            id: detail.id,
                            name: detail.name,
                            description: detail.description,
                            enabled: !detail.enabled,
                            trigger: detail.trigger,
                            steps: detail.steps,
                            notifyOnStart: detail.notifyOnStart,
                            notifyOnComplete: detail.notifyOnComplete,
                            notifyOnError: detail.notifyOnError,
                            notifyOnStepComplete: detail.notifyOnStepComplete
                        )
                        workflowVM.updateWorkflow(detail)
                    }
                }
            ))
            .labelsHidden()
            .tint(.heart)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.trust)
        }
        .padding(.vertical, LoveMeTheme.xs)
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
            .padding(.horizontal, LoveMeTheme.sm)
            .padding(.vertical, 2)
            .background(
                (type == "cron" ? Color.electricBlue : Color.amberGlow).opacity(0.15)
            )
            .clipShape(Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: LoveMeTheme.md) {
            Spacer()
                .frame(height: 80)

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(.trust.opacity(0.5))

            Text("No workflows yet")
                .font(.chatMessage)
                .foregroundStyle(.trust)

            Text("Tap + to create your first workflow.")
                .font(.toolDetail)
                .foregroundStyle(.trust.opacity(0.7))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var skeletonRow: some View {
        HStack(spacing: LoveMeTheme.md) {
            Circle()
                .fill(Color.surfaceElevated)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: LoveMeTheme.sm) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.surfaceElevated)
                    .frame(width: 160, height: 16)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.surfaceElevated.opacity(0.6))
                    .frame(width: 80, height: 12)
            }

            Spacer()
        }
        .padding(.vertical, LoveMeTheme.xs)
        .redacted(reason: .placeholder)
    }
}
