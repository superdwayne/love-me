import SwiftUI

struct WorkflowPreviewCard: View {
    let name: String
    let scheduleDescription: String
    let steps: [PreviewStep]
    var isEnabled: Bool = true
    var needsConfiguration: Bool = false

    struct PreviewStep: Identifiable {
        let id: String
        let name: String
        let toolName: String
        var needsConfig: Bool = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.md) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                    Text(name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.textPrimary)

                    HStack(spacing: SolaceTheme.sm) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundStyle(.electricBlue)
                        Text(scheduleDescription)
                            .font(.toolDetail)
                            .foregroundStyle(.trust)
                    }
                }

                Spacer()

                // Step count badge
                Text("\(steps.count) step\(steps.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.trust)
                    .padding(.horizontal, SolaceTheme.sm)
                    .padding(.vertical, SolaceTheme.xs)
                    .background(Color.surfaceElevated)
                    .clipShape(Capsule())
            }

            // Step pipeline
            if !steps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        WorkflowStepCard(
                            mode: .preview,
                            index: index,
                            name: step.name,
                            toolName: step.toolName,
                            serverName: "",
                            needsConfig: step.needsConfig
                        )

                        if index < steps.count - 1 {
                            HStack {
                                Rectangle()
                                    .fill(Color.trust.opacity(0.3))
                                    .frame(width: 2, height: 20)
                                    .padding(.leading, 18)
                                Spacer()
                            }
                        }
                    }
                }
            }

            // Warning if needs configuration
            if needsConfiguration {
                HStack(spacing: SolaceTheme.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.amberGlow)
                    Text("Some steps need tool configuration")
                        .font(.timestamp)
                        .foregroundStyle(.amberGlow)
                }
                .padding(.top, SolaceTheme.xs)
            }
        }
        .padding(SolaceTheme.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}
