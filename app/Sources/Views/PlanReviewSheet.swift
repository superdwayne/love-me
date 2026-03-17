import SwiftUI

struct PlanReviewSheet: View {
    @Environment(AgentPlanViewModel.self) private var planVM
    @Environment(\.dismiss) private var dismiss
    @State private var showEditView = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let plan = planVM.currentPlan {
                    VStack(alignment: .leading, spacing: SolaceTheme.lg) {
                        // Header
                        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                            Text(plan.name)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.textPrimary)
                            Text(plan.description)
                                .font(.system(size: 15))
                                .foregroundStyle(.textSecondary)
                        }
                        .padding(.horizontal, SolaceTheme.lg)

                        // Cost estimate if available
                        if let cost = plan.estimatedCost {
                            HStack {
                                Image(systemName: "dollarsign.circle")
                                    .foregroundStyle(.textSecondary)
                                Text("Estimated cost: $\(String(format: "%.4f", cost))")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.textSecondary)
                            }
                            .padding(.horizontal, SolaceTheme.lg)
                        }

                        // Agent summary
                        HStack(spacing: SolaceTheme.lg) {
                            StatBadge(label: "Agents", value: "\(plan.agents.count)", icon: "person.3")
                            StatBadge(label: "Waves", value: "\(plan.dependencyWaves.count)", icon: "arrow.triangle.branch")
                        }
                        .padding(.horizontal, SolaceTheme.lg)

                        // Dependency waves
                        ForEach(Array(plan.dependencyWaves.enumerated()), id: \.offset) { waveIndex, wave in
                            VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                                Text("WAVE \(waveIndex + 1)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.textSecondary)
                                    .tracking(1.2)

                                ForEach(wave, id: \.id) { agent in
                                    AgentPlanCard(agent: agent, allAgents: plan.agents)
                                }
                            }
                            .padding(.horizontal, SolaceTheme.lg)
                        }
                    }
                    .padding(.vertical, SolaceTheme.lg)
                }
            }
            .background(.appBackground)
            .navigationTitle("Review Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reject") {
                        planVM.rejectPlan()
                        dismiss()
                    }
                    .foregroundStyle(.softRed)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        showEditView = true
                    }
                    .foregroundStyle(.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    planVM.approvePlan()
                    dismiss()
                } label: {
                    HStack(spacing: SolaceTheme.sm) {
                        Image(systemName: "play.fill")
                        Text("Approve & Execute")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SolaceTheme.md)
                    .background(Color.heart)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, SolaceTheme.lg)
                .padding(.vertical, SolaceTheme.sm)
                .background(.appBackground)
            }
            .fullScreenCover(isPresented: $showEditView) {
                PlanEditView()
            }
        }
    }
}

// MARK: - Agent Plan Card

struct AgentPlanCard: View {
    let agent: AgentTask
    let allAgents: [AgentTask]

    var body: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            HStack {
                Text(agent.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.textPrimary)
                Spacer()
                ProviderBadge(spec: agent.providerSpec)
            }

            Text(agent.objective)
                .font(.system(size: 13))
                .foregroundStyle(.textSecondary)
                .lineLimit(3)

            if !agent.requiredTools.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SolaceTheme.xs) {
                        ForEach(agent.requiredTools, id: \.self) { tool in
                            Text(tool)
                                .font(.system(size: 11))
                                .foregroundStyle(.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.textSecondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            if let deps = agent.dependsOn, !deps.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.textSecondary.opacity(0.6))
                    Text("Depends on: \(deps.compactMap { depId in allAgents.first(where: { $0.id == depId })?.name }.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary.opacity(0.6))
                }
            }
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Provider Badge

struct ProviderBadge: View {
    let spec: AgentProviderSpec

    private var color: Color {
        switch spec.providerColor {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "green": return .green
        default: return .gray
        }
    }

    var body: some View {
        Text(spec.displayName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: SolaceTheme.xs) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.textSecondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.textPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.textSecondary)
        }
        .padding(.horizontal, SolaceTheme.md)
        .padding(.vertical, SolaceTheme.sm)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
