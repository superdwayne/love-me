import SwiftUI

struct AgentDetailView: View {
    let agentId: String
    @Environment(AgentPlanViewModel.self) private var planVM

    private var agent: AgentTask? {
        planVM.currentPlan?.agents.first(where: { $0.id == agentId })
    }

    private var result: AgentResult? {
        planVM.currentExecution?.agentResults.first(where: { $0.agentId == agentId })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SolaceTheme.lg) {
                // Header
                if let agent = agent, let result = result {
                    agentHeader(agent: agent, result: result)
                }

                // Provider fallback notice
                if let fallback = planVM.agentFallbacks[agentId] {
                    fallbackNotice(fallback)
                }

                // Thinking panel (expandable)
                if let thinking = planVM.agentThinking[agentId], !thinking.isEmpty {
                    thinkingSection(thinking)
                }

                // Conversation / streaming output
                if let stream = planVM.agentStreams[agentId], !stream.isEmpty {
                    outputSection(stream)
                }

                // Final output
                if let output = result?.output, result?.status == .success {
                    finalOutputSection(output)
                }

                // Error
                if let error = result?.error, result?.status == .error {
                    errorSection(error)
                }
            }
            .padding(SolaceTheme.lg)
        }
        .background(.appBackground)
        .navigationTitle(agent?.name ?? "Agent Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func agentHeader(agent: AgentTask, result: AgentResult) -> some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.textPrimary)
                    Text(agent.objective)
                        .font(.system(size: 14))
                        .foregroundStyle(.trust)
                }
                Spacer()
                ProviderBadge(spec: agent.providerSpec)
            }

            HStack(spacing: SolaceTheme.lg) {
                Label("\(result.turnCount) turns", systemImage: "arrow.triangle.2.circlepath")
                Label("\(result.toolCallCount) tools", systemImage: "wrench")
                if let started = result.startedAt, let completed = result.completedAt {
                    let duration = completed.timeIntervalSince(started)
                    Label("\(Int(duration))s", systemImage: "clock")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.trust)
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func thinkingSection(_ thinking: String) -> some View {
        DisclosureGroup {
            Text(thinking)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.trust.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SolaceTheme.sm)
        } label: {
            HStack(spacing: SolaceTheme.xs) {
                Image(systemName: "brain")
                    .foregroundStyle(.purple)
                Text("Thinking")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.textPrimary)
            }
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func outputSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            Text("OUTPUT")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.trust)
                .tracking(1.2)

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func finalOutputSection(_ output: String) -> some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.sageGreen)
                Text("FINAL OUTPUT")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.sageGreen)
                    .tracking(1.2)
                Spacer()
                Button {
                    UIPasteboard.general.string = output
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(.trust)
                }
            }

            Text(output)
                .font(.system(size: 14))
                .foregroundStyle(.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SolaceTheme.md)
        .background(Color.sageGreen.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sageGreen.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func fallbackNotice(_ fallback: (from: String, to: String, reason: String)) -> some View {
        HStack(spacing: SolaceTheme.sm) {
            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Provider Fallback")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.orange)
                Text("Switched from \(fallback.from) to \(fallback.to): \(fallback.reason)")
                    .font(.system(size: 12))
                    .foregroundStyle(.trust)
            }
        }
        .padding(SolaceTheme.md)
        .background(Color.orange.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.softRed)
                Text("ERROR")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.softRed)
                    .tracking(1.2)
            }

            Text(error)
                .font(.system(size: 14))
                .foregroundStyle(.softRed)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SolaceTheme.md)
        .background(Color.softRed.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.softRed.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
