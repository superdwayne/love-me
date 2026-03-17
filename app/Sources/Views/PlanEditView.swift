import SwiftUI

struct PlanEditView: View {
    @Environment(AgentPlanViewModel.self) private var planVM
    @Environment(\.dismiss) private var dismiss
    @State private var editableAgents: [EditableAgent] = []
    @State private var showCircularWarning = false

    struct EditableAgent: Identifiable {
        let id: String
        var name: String
        var objective: String
        var provider: String
        var maxTurns: Int
        var requiredTools: [String]
        var dependsOn: [String]
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach($editableAgents) { $agent in
                    Section {
                        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                            // Name
                            TextField("Agent Name", text: $agent.name)
                                .font(.system(size: 15, weight: .semibold))

                            // Objective
                            TextField("Objective", text: $agent.objective, axis: .vertical)
                                .font(.system(size: 14))
                                .lineLimit(3...6)

                            // Provider picker
                            HStack {
                                Text("Model")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.textSecondary)
                                Spacer()
                                Picker("Model", selection: $agent.provider) {
                                    Text("Claude Haiku").tag("claude:haiku")
                                    Text("Claude Sonnet").tag("claude:sonnet")
                                    Text("Claude Opus").tag("claude:opus")
                                    Text("GPT-4o").tag("openai:gpt-4o")
                                    Text("GPT-4o-mini").tag("openai:gpt-4o-mini")
                                }
                                .pickerStyle(.menu)
                            }

                            // Max turns
                            Stepper("Max turns: \(agent.maxTurns)", value: $agent.maxTurns, in: 1...50)
                                .font(.system(size: 13))
                                .foregroundStyle(.textSecondary)

                            // Dependencies
                            if editableAgents.count > 1 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Depends on:")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.textSecondary)

                                    let otherAgents = editableAgents.filter { $0.id != agent.id }
                                    FlowLayout(spacing: 6) {
                                        ForEach(otherAgents) { other in
                                            let isSelected = agent.dependsOn.contains(other.id)
                                            Button {
                                                if isSelected {
                                                    agent.dependsOn.removeAll { $0 == other.id }
                                                } else {
                                                    agent.dependsOn.append(other.id)
                                                }
                                            } label: {
                                                Text(other.name)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(isSelected ? .white : .textSecondary)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(isSelected ? Color.heart : Color.textSecondary.opacity(0.1))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .listRowBackground(Color.surface)
                    } header: {
                        HStack {
                            Text("AGENT \(editableAgents.firstIndex(where: { $0.id == agent.id }).map { $0 + 1 } ?? 0)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.textSecondary)
                                .tracking(1.2)
                        }
                    }
                }
                .onDelete(perform: deleteAgent)

                // Add Agent button
                Section {
                    Button {
                        addAgent()
                    } label: {
                        HStack(spacing: SolaceTheme.sm) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Agent")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.heart)
                    }
                    .listRowBackground(Color.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(.appBackground)
            .navigationTitle("Edit Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save & Approve") {
                        if hasCircularDependencies() {
                            showCircularWarning = true
                        } else {
                            saveAndApprove()
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.heart)
                }
            }
            .alert("Circular Dependencies", isPresented: $showCircularWarning) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The agent dependencies form a cycle. Please fix before saving.")
            }
            .onAppear {
                loadPlan()
            }
        }
    }

    private func loadPlan() {
        guard let plan = planVM.currentPlan else { return }
        editableAgents = plan.agents.map { agent in
            EditableAgent(
                id: agent.id,
                name: agent.name,
                objective: agent.objective,
                provider: "\(agent.providerSpec.providerName.lowercased()):\(agent.providerSpec.modelName)",
                maxTurns: agent.maxTurns,
                requiredTools: agent.requiredTools,
                dependsOn: agent.dependsOn ?? []
            )
        }
    }

    private func addAgent() {
        editableAgents.append(EditableAgent(
            id: UUID().uuidString,
            name: "New Agent",
            objective: "",
            provider: "claude:sonnet",
            maxTurns: 10,
            requiredTools: [],
            dependsOn: []
        ))
    }

    private func deleteAgent(at offsets: IndexSet) {
        let idsToRemove = offsets.map { editableAgents[$0].id }
        editableAgents.remove(atOffsets: offsets)
        // Clean up dependencies referencing deleted agents
        for i in editableAgents.indices {
            editableAgents[i].dependsOn.removeAll { idsToRemove.contains($0) }
        }
    }

    private func hasCircularDependencies() -> Bool {
        var visited = Set<String>()
        var inStack = Set<String>()
        let agentMap = Dictionary(uniqueKeysWithValues: editableAgents.map { ($0.id, $0) })

        func dfs(_ id: String) -> Bool {
            if inStack.contains(id) { return true }
            if visited.contains(id) { return false }
            visited.insert(id)
            inStack.insert(id)
            for dep in agentMap[id]?.dependsOn ?? [] {
                if dfs(dep) { return true }
            }
            inStack.remove(id)
            return false
        }

        return editableAgents.contains { dfs($0.id) }
    }

    private func saveAndApprove() {
        guard let plan = planVM.currentPlan else { return }

        let metadata: [String: MetadataValue] = [
            "planId": .string(plan.id),
            "agents": .array(editableAgents.map { agent in
                .object([
                    "id": .string(agent.id),
                    "name": .string(agent.name),
                    "objective": .string(agent.objective),
                    "provider": .string(agent.provider),
                    "maxTurns": .int(agent.maxTurns),
                    "dependsOn": .array(agent.dependsOn.map { .string($0) })
                ])
            })
        ]

        planVM.sendEditAndApprove(metadata: metadata)
        dismiss()
    }
}

// MARK: - Flow Layout for dependency chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
