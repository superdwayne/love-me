import SwiftUI

struct AgentDashboardView: View {
    @Environment(AgentPlanViewModel.self) private var planVM

    private var elapsedTime: String {
        guard let execution = planVM.currentExecution else { return "0s" }
        let elapsed = Date().timeIntervalSince(execution.startedAt)
        if elapsed < 60 { return "\(Int(elapsed))s" }
        return "\(Int(elapsed / 60))m \(Int(elapsed.truncatingRemainder(dividingBy: 60)))s"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SolaceTheme.lg) {
                    // Progress header
                    if let execution = planVM.currentExecution {
                        progressHeader(execution)
                    }

                    // Agent cards grouped by wave
                    if let plan = planVM.currentPlan {
                        ForEach(Array(plan.dependencyWaves.enumerated()), id: \.offset) { waveIndex, wave in
                            VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                                Text("WAVE \(waveIndex + 1)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.trust)
                                    .tracking(1.2)

                                ForEach(wave, id: \.id) { agent in
                                    NavigationLink {
                                        AgentDetailView(agentId: agent.id)
                                    } label: {
                                        AgentExecutionCard(
                                            agent: agent,
                                            result: planVM.currentExecution?.agentResults.first(where: { $0.agentId == agent.id }),
                                            streamText: planVM.agentStreams[agent.id],
                                            toolActivity: planVM.agentToolActivity[agent.id]
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, SolaceTheme.lg)
                        }
                    }
                }
                .padding(.vertical, SolaceTheme.lg)
            }
            .background(.appBackground)
            .navigationTitle(planVM.currentPlan?.name ?? "Agent Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if planVM.isExecuting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") {
                            planVM.cancelExecution()
                        }
                        .foregroundStyle(.softRed)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func progressHeader(_ execution: AgentExecution) -> some View {
        VStack(spacing: SolaceTheme.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(execution.completedAgentCount)/\(execution.agentResults.count) agents complete")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.textPrimary)
                    Text("Elapsed: \(elapsedTime)")
                        .font(.system(size: 12))
                        .foregroundStyle(.trust)
                }
                Spacer()
                statusBadge(execution.status)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.trust.opacity(0.1))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(execution.status == .failed ? Color.softRed : Color.sageGreen)
                        .frame(width: geo.size.width * progressFraction(execution))
                        .animation(.easeInOut(duration: 0.3), value: execution.completedAgentCount)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, SolaceTheme.lg)
    }

    private func progressFraction(_ execution: AgentExecution) -> CGFloat {
        guard !execution.agentResults.isEmpty else { return 0 }
        let done = execution.agentResults.filter { $0.status == .success || $0.status == .error }.count
        return CGFloat(done) / CGFloat(execution.agentResults.count)
    }

    @ViewBuilder
    private func statusBadge(_ status: AgentExecutionStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .pending: return ("Pending", .trust)
            case .running: return ("Running", .blue)
            case .completed: return ("Complete", .sageGreen)
            case .failed: return ("Failed", .softRed)
            case .cancelled: return ("Cancelled", .trust)
            }
        }()

        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Agent Execution Card

struct AgentExecutionCard: View {
    let agent: AgentTask
    let result: AgentResult?
    let streamText: String?
    let toolActivity: String?

    private var statusColor: Color {
        switch result?.status {
        case .running: return .blue
        case .success: return .sageGreen
        case .error: return .softRed
        case .spawning: return .orange
        default: return .trust.opacity(0.4)
        }
    }

    private var statusIcon: String {
        switch result?.status {
        case .running: return "circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .spawning: return "arrow.triangle.branch"
        default: return "circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            HStack {
                // Status indicator
                Image(systemName: statusIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, isActive: result?.status == .running)

                Text(agent.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.textPrimary)

                Spacer()

                ProviderBadge(spec: agent.providerSpec)
            }

            // Streaming text preview for running agents
            if result?.status == .running, let text = streamText, !text.isEmpty {
                Text(String(text.suffix(150)))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.trust)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SolaceTheme.sm)
                    .background(Color.appBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Tool activity
            if let tool = toolActivity {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Running \(tool)...")
                        .font(.system(size: 11))
                        .foregroundStyle(.trust)
                }
            }

            // Completed output preview
            if result?.status == .success, let output = result?.output {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.sageGreen)
                    Text(String(output.prefix(100)))
                        .font(.system(size: 12))
                        .foregroundStyle(.trust)
                        .lineLimit(2)
                }
            }

            // Error message
            if result?.status == .error, let error = result?.error {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.softRed)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.softRed)
                        .lineLimit(2)
                }
            }
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
