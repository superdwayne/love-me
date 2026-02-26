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
        VStack(alignment: .leading, spacing: LoveMeTheme.md) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: LoveMeTheme.xs) {
                    Text(name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.textPrimary)

                    HStack(spacing: LoveMeTheme.sm) {
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
                    .padding(.horizontal, LoveMeTheme.sm)
                    .padding(.vertical, LoveMeTheme.xs)
                    .background(Color.surfaceElevated)
                    .clipShape(Capsule())
            }

            // Step pipeline
            if !steps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        stepPill(step)

                        if index < steps.count - 1 {
                            // Connector arrow
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
                HStack(spacing: LoveMeTheme.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.amberGlow)
                    Text("Some steps need tool configuration")
                        .font(.timestamp)
                        .foregroundStyle(.amberGlow)
                }
                .padding(.top, LoveMeTheme.xs)
            }
        }
        .padding(LoveMeTheme.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(isEnabled ? 1.0 : 0.6)
    }

    private func stepPill(_ step: PreviewStep) -> some View {
        HStack(spacing: LoveMeTheme.sm) {
            // Step icon
            Circle()
                .fill(step.needsConfig ? Color.amberGlow.opacity(0.2) : Color.electricBlue.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: step.needsConfig ? "questionmark" : "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(step.needsConfig ? .amberGlow : .electricBlue)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)

                Text(step.toolName)
                    .font(.timestamp)
                    .foregroundStyle(.trust)
                    .lineLimit(1)
            }

            Spacer()

            // Status indicator
            Circle()
                .fill(step.needsConfig ? Color.amberGlow : Color.sageGreen)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, LoveMeTheme.md)
        .padding(.vertical, LoveMeTheme.sm)
        .background(Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
