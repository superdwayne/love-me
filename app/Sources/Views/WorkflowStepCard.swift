import SwiftUI

enum StepCardMode {
    case readOnly
    case editable
    case execution
    case preview
}

struct WorkflowStepCard: View {
    let mode: StepCardMode
    let index: Int
    let name: String
    let toolName: String
    let serverName: String
    var inputs: [String: String] = [:]
    var needsConfig: Bool = false
    var status: String = "pending"
    var output: String?
    var error: String?
    var startedAt: Date?
    var completedAt: Date?
    var isExpanded: Bool = false
    var onToggleExpand: (() -> Void)?

    // Editable mode bindings
    var onNameChanged: ((String) -> Void)?
    var onInputChanged: ((String, String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Button {
                onToggleExpand?()
            } label: {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
        .overlay(
            RoundedRectangle(cornerRadius: SolaceTheme.sm)
                .strokeBorder(Color.divider, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(borderColor)
                .frame(width: SolaceTheme.toolCardLeftBorderWidth)
                .padding(.vertical, SolaceTheme.xs)
        }
        .shadow(color: status == "running" ? Color.info.opacity(pulseOpacity) : .clear, radius: 6)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: SolaceTheme.sm) {
            // Step number
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.textSecondary)
                .frame(width: 20, height: 20)
                .background(Color.surfaceElevated)
                .clipShape(Circle())

            // Tool icon
            toolIcon
                .frame(width: 20, height: 20)

            // Name and tool info
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Step \(index + 1)" : name)
                    .font(.toolTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)

                if mode != .preview {
                    HStack(spacing: SolaceTheme.xs) {
                        Text(toolName)
                            .font(.timestamp)
                            .foregroundStyle(.textSecondary)
                            .lineLimit(1)

                        if !serverName.isEmpty {
                            Text("·")
                                .foregroundStyle(.textSecondary)
                            Text(serverName)
                                .font(.timestamp)
                                .foregroundStyle(.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer()

            // Status-dependent trailing content
            trailingContent

            if mode != .preview {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(duration: SolaceTheme.springDuration), value: isExpanded)
            }
        }
        .padding(.horizontal, SolaceTheme.md)
        .frame(minHeight: SolaceTheme.toolCardCollapsedHeight)
    }

    // MARK: - Tool Icon

    @ViewBuilder
    private var toolIcon: some View {
        let (iconName, iconColor) = Self.toolIcon(for: toolName)
        Image(systemName: iconName)
            .font(.system(size: 14))
            .foregroundStyle(iconColor)
    }

    static func toolIcon(for toolName: String) -> (String, Color) {
        let lower = toolName.lowercased()
        if lower.contains("file") || lower.contains("read") || lower.contains("write") {
            return ("doc.text", .amberGlow)
        }
        if lower.contains("network") || lower.contains("fetch") || lower.contains("api") || lower.contains("http") {
            return ("network", .electricBlue)
        }
        if lower.contains("ai") || lower.contains("generate") || lower.contains("llm") || lower.contains("claude") {
            return ("brain.head.profile", .heart)
        }
        if lower.contains("email") || lower.contains("send") || lower.contains("mail") {
            return ("paperplane", .sageGreen)
        }
        if lower.contains("bash") || lower.contains("shell") || lower.contains("command") || lower.contains("exec") {
            return ("terminal", .electricBlue)
        }
        return ("gearshape", .textSecondary)
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case "running":
            ProgressView()
                .scaleEffect(0.7)
                .tint(.electricBlue)
        case "success":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.sageGreen)
        case "error":
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.softRed)
        case "skipped":
            Image(systemName: "slash.circle")
                .font(.system(size: 14))
                .foregroundStyle(.textSecondary)
        default:
            Circle()
                .strokeBorder(Color.textSecondary.opacity(0.4), lineWidth: 1.5)
                .frame(width: 14, height: 14)
        }
    }

    // MARK: - Trailing Content

    @ViewBuilder
    private var trailingContent: some View {
        switch mode {
        case .execution:
            HStack(spacing: SolaceTheme.sm) {
                if let duration = stepDuration {
                    Text(formatDuration(duration))
                        .font(.toolDetail)
                        .monospacedDigit()
                        .foregroundStyle(.textSecondary)
                }
                statusIcon
            }
        case .readOnly:
            if !inputs.isEmpty {
                Text("\(inputs.count) input\(inputs.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.sageGreen)
                    .padding(.horizontal, SolaceTheme.sm)
                    .padding(.vertical, 2)
                    .background(Color.sageGreen.opacity(0.12))
                    .clipShape(Capsule())
            }
        case .preview:
            Circle()
                .fill(needsConfig ? Color.amberGlow : Color.sageGreen)
                .frame(width: 8, height: 8)
        case .editable:
            EmptyView()
        }
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            Divider()
                .background(.divider)

            switch mode {
            case .execution:
                executionExpandedContent
            case .readOnly:
                readOnlyExpandedContent
            case .editable:
                editableExpandedContent
            case .preview:
                EmptyView()
            }
        }
        .padding(.horizontal, SolaceTheme.md)
        .padding(.bottom, SolaceTheme.md)
    }

    private var executionExpandedContent: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            if let startedAt {
                HStack(spacing: SolaceTheme.sm) {
                    Text("Started")
                        .font(.timestamp)
                        .foregroundStyle(.textSecondary)
                    Text(startedAt.formatted(date: .omitted, time: .standard))
                        .font(.toolDetail)
                        .foregroundStyle(.textPrimary)
                }
            }

            if let completedAt {
                HStack(spacing: SolaceTheme.sm) {
                    Text("Completed")
                        .font(.timestamp)
                        .foregroundStyle(.textSecondary)
                    Text(completedAt.formatted(date: .omitted, time: .standard))
                        .font(.toolDetail)
                        .foregroundStyle(.textPrimary)
                }
            }

            if let output, !output.isEmpty {
                VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                    Text("OUTPUT")
                        .font(.sectionHeader)
                        .foregroundStyle(.textSecondary)
                        .tracking(1.2)

                    Text(output)
                        .font(.toolDetail)
                        .foregroundStyle(.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SolaceTheme.sm)
                        .background(.codeBg)
                        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.xs))
                        .lineLimit(10)
                }
            }

            if let error, !error.isEmpty {
                VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                    Text("ERROR")
                        .font(.sectionHeader)
                        .foregroundStyle(.softRed)
                        .tracking(1.2)

                    Text(error)
                        .font(.toolDetail)
                        .foregroundStyle(.softRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SolaceTheme.sm)
                        .background(.codeBg)
                        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.xs))
                }
            }
        }
    }

    private var readOnlyExpandedContent: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            if !inputs.isEmpty {
                Text("INPUTS")
                    .font(.sectionHeader)
                    .foregroundStyle(.textSecondary)
                    .tracking(1.2)

                ForEach(Array(inputs.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                    HStack(alignment: .top, spacing: SolaceTheme.sm) {
                        Text(key)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.electricBlue)
                            .frame(minWidth: 60, alignment: .leading)

                        Text(value)
                            .font(.toolDetail)
                            .foregroundStyle(.textPrimary)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    private var editableExpandedContent: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            ForEach(Array(inputs.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                    Text(key)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.textSecondary)

                    TextField("Value", text: Binding(
                        get: { value },
                        set: { onInputChanged?(key, $0) }
                    ))
                    .font(.toolDetail)
                    .foregroundStyle(.textPrimary)
                    .padding(SolaceTheme.sm)
                    .background(Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.xs))
                }
            }
        }
    }

    // MARK: - Helpers

    private var borderColor: Color {
        switch status {
        case "running": return .electricBlue
        case "success": return .sageGreen
        case "error": return .softRed
        case "skipped": return .textSecondary.opacity(0.4)
        default:
            if mode == .execution {
                return .textSecondary.opacity(0.2)
            }
            if needsConfig {
                return .amberGlow.opacity(0.5)
            }
            return .electricBlue.opacity(0.3)
        }
    }

    @State private var pulseOpacity: Double = 0.3

    private var stepDuration: TimeInterval? {
        guard let start = startedAt else { return nil }
        if let end = completedAt {
            return end.timeIntervalSince(start)
        }
        if status == "running" {
            return Date().timeIntervalSince(start)
        }
        return nil
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return String(format: "%.0fms", interval * 1000)
        } else if interval < 60 {
            return String(format: "%.1fs", interval)
        } else {
            let minutes = Int(interval) / 60
            let seconds = Int(interval) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}
