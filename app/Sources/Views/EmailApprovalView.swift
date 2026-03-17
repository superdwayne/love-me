import SwiftUI

struct EmailApprovalView: View {
    let approval: EmailApprovalDisplay
    let onChat: () -> Void
    let onAutoWorkflow: () -> Void
    let onSaveAutoFlow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.md) {
            // Header: from + time
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.heart)

                Text("Email Brief")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.heart)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.heart.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                Text(relativeDate(approval.createdAt))
                    .font(.timestamp)
                    .foregroundStyle(.textSecondary)
            }

            // Email info
            VStack(alignment: .leading, spacing: 4) {
                Text(approval.emailSubject)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(2)

                Text("From: \(approval.emailFrom)")
                    .font(.toolDetail)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }

            // AI summary
            if let summary = approval.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.textPrimary.opacity(0.85))
                    .lineLimit(3)
                    .padding(SolaceTheme.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if !approval.emailPreview.isEmpty {
                Text(approval.emailPreview)
                    .font(.system(size: 13))
                    .foregroundStyle(.textSecondary.opacity(0.7))
                    .lineLimit(2)
            }

            // Recommendation hint
            if let hint = approval.recommendationLabel {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text(hint)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.amberGlow)
            }

            // Action buttons or status
            if approval.isPending {
                VStack(spacing: SolaceTheme.sm) {
                    HStack(spacing: SolaceTheme.sm) {
                        // Dismiss (tertiary)
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.textSecondary)
                                .frame(width: 40, height: 36)
                                .background(Color.textSecondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Chat (primary when recommended)
                        Button(action: onChat) {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                Text("Chat")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(approval.recommendation == "chat" ? .white : .electricBlue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SolaceTheme.sm)
                            .background(approval.recommendation == "chat" ? Color.electricBlue : Color.electricBlue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Auto Workflow (primary when recommended)
                        Button(action: onAutoWorkflow) {
                            HStack(spacing: 4) {
                                Image(systemName: "gearshape")
                                Text("Auto")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(approval.recommendation == "workflow" ? .white : .sageGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SolaceTheme.sm)
                            .background(approval.recommendation == "workflow" ? Color.sageGreen : Color.sageGreen.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // Save Auto Flow (full width, second row)
                    Button(action: onSaveAutoFlow) {
                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                            Text("Save as Auto Flow")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.amberGlow)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SolaceTheme.sm)
                        .background(Color.amberGlow.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            } else if approval.isBuilding {
                HStack(spacing: SolaceTheme.sm) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.amberGlow)
                    Text("Building workflow...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.amberGlow)
                }
            } else {
                HStack(spacing: SolaceTheme.sm) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(statusColor)
                    Text(approval.statusLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(statusColor)
                }
            }
        }
        .padding(SolaceTheme.md)
    }

    private var statusIcon: String {
        switch approval.status {
        case "approved": return "arrow.triangle.2.circlepath"
        case "completed": return "checkmark.circle.fill"
        case "failed": return "exclamationmark.triangle.fill"
        case "dismissed": return "xmark.circle.fill"
        default: return "clock"
        }
    }

    private var statusColor: Color {
        switch approval.status {
        case "approved": return .electricBlue
        case "completed": return .sageGreen
        case "failed": return .softRed
        case "dismissed": return .textSecondary
        default: return .amberGlow
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
