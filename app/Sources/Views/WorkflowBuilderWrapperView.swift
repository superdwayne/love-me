import SwiftUI

struct WorkflowBuilderWrapperView: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    @Environment(\.dismiss) private var dismiss

    // MARK: - Phase

    enum Phase: Equatable {
        case prompt
        case building
        case result
        case manual
    }

    @State private var phase: Phase = .prompt
    @State private var appeared = false

    // AI prompt
    @State private var promptText = ""
    @FocusState private var isPromptFocused: Bool

    // Building animation
    @State private var buildPulse = false
    @State private var gearRotation: Double = 0

    // Manual builder state
    @State private var workflowName = ""
    @State private var workflowDescription = ""
    @State private var triggerType = "manual"
    @State private var cronExpression = ""
    @State private var scheduleText = ""
    @State private var useRawCron = false
    @State private var scheduleDebounceTask: Task<Void, Never>?
    @State private var deckCards: [EditableStep] = []
    @State private var notifyOnStart = false
    @State private var notifyOnComplete = true
    @State private var notifyOnError = true
    @State private var notifyOnStepComplete = false
    @State private var showManualOptions = false
    @State private var showTriggerConfig = false

    private var isManualValid: Bool {
        !workflowName.trimmingCharacters(in: .whitespaces).isEmpty && !deckCards.isEmpty
    }

    private var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespaces).isEmpty && !workflowVM.isBuilding
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                switch phase {
                case .prompt:
                    promptView
                        .transition(.opacity)
                case .building:
                    buildingView
                        .transition(.opacity)
                case .result:
                    resultView
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.96).combined(with: .opacity),
                            removal: .opacity
                        ))
                case .manual:
                    manualView
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: phase)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { handleBack() } label: {
                        if phase == .prompt {
                            Text("Cancel")
                                .font(.inter(size: 16))
                                .foregroundStyle(.textSecondary)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Back")
                                    .font(.inter(size: 16))
                            }
                            .foregroundStyle(.textSecondary)
                        }
                    }
                }
                if phase == .manual {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { saveManual() }
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundStyle(isManualValid ? .coral : .textSecondary.opacity(0.4))
                            .disabled(!isManualValid)
                    }
                }
            }
            .toolbarBackground(.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Back Navigation

    private func handleBack() {
        switch phase {
        case .prompt:
            dismiss()
        case .building:
            // Can't go back while building
            break
        case .result:
            workflowVM.builderResult = nil
            workflowVM.builderError = nil
            promptText = ""
            withAnimation { phase = .prompt }
        case .manual:
            withAnimation { phase = .prompt }
        }
    }

    // MARK: ──────────────────────────────────────────────────────────────────
    // MARK: Phase 1 — Prompt
    // MARK: ──────────────────────────────────────────────────────────────────

    private var promptView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: SolaceTheme.xxl) {
                    Spacer().frame(height: 32)

                    // Hero
                    heroSection

                    // Prompt input
                    promptInputSection

                    // Error from previous attempt
                    if let error = workflowVM.builderError {
                        errorBanner(error)
                            .padding(.horizontal, 20)
                    }

                    // Examples
                    examplesSection

                    Spacer().frame(height: 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            // Manual builder link
            manualEntryLink
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.05)) {
                appeared = true
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: SolaceTheme.lg) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(Color.coral.opacity(0.08))
                    .frame(width: 80, height: 80)

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.coral)
            }
            .scaleEffect(appeared ? 1.0 : 0.6)
            .opacity(appeared ? 1.0 : 0)

            VStack(spacing: SolaceTheme.sm) {
                Text("What should this\nworkflow do?")
                    .font(.displayTitle)
                    .foregroundStyle(.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Describe it naturally — I'll build the steps.")
                    .font(.chatMessage)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(appeared ? 1.0 : 0)
            .offset(y: appeared ? 0 : 10)
        }
    }

    private var promptInputSection: some View {
        VStack(spacing: SolaceTheme.md) {
            // Text field
            TextField(
                "e.g. Every morning, summarize my unread emails...",
                text: $promptText,
                axis: .vertical
            )
            .font(.chatMessage)
            .foregroundStyle(.textPrimary)
            .lineLimit(3...8)
            .focused($isPromptFocused)
            .padding(SolaceTheme.lg)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SolaceTheme.cardRadius)
                    .strokeBorder(
                        isPromptFocused ? Color.coral.opacity(0.5) : Color.divider,
                        lineWidth: isPromptFocused ? 1.5 : 1
                    )
            )
            .shadow(
                color: isPromptFocused ? .coral.opacity(0.06) : .clear,
                radius: 16
            )

            // Build button
            Button { sendPrompt() } label: {
                HStack(spacing: SolaceTheme.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Build Workflow")
                        .font(.bodyMedium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    canSend
                        ? AnyShapeStyle(Color.coral)
                        : AnyShapeStyle(Color.textSecondary.opacity(0.15))
                )
                .clipShape(Capsule())
                .shadow(
                    color: canSend ? .coral.opacity(0.15) : .clear,
                    radius: 8, y: 4
                )
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 20)
        .opacity(appeared ? 1.0 : 0)
        .offset(y: appeared ? 0 : 16)
    }

    private var examplesSection: some View {
        VStack(spacing: SolaceTheme.sm) {
            Text("Try an example")
                .font(.caption)
                .foregroundStyle(.textSecondary)

            VStack(spacing: SolaceTheme.sm) {
                exampleChip(
                    "Every 5 minutes, generate a 3D asset in Blender",
                    icon: "cube"
                )
                exampleChip(
                    "Daily at 9am, read my notes and summarize them",
                    icon: "doc.text"
                )
                exampleChip(
                    "Every hour, check disk space and alert if low",
                    icon: "internaldrive"
                )
            }
        }
        .padding(.horizontal, 20)
        .opacity(appeared ? 1.0 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    private func exampleChip(_ text: String, icon: String) -> some View {
        Button {
            promptText = text
            sendPrompt()
        } label: {
            HStack(spacing: SolaceTheme.md) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.coral.opacity(0.6))
                    .frame(width: 20)

                Text(text)
                    .font(.caption)
                    .foregroundStyle(.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.textSecondary.opacity(0.4))
            }
            .padding(.horizontal, SolaceTheme.lg)
            .padding(.vertical, SolaceTheme.md)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: SolaceTheme.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.error)
            Text(error)
                .font(.caption)
                .foregroundStyle(.textPrimary)
            Spacer()
            Button {
                workflowVM.builderError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.textSecondary)
            }
        }
        .padding(SolaceTheme.md)
        .background(Color.error.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.error.opacity(0.2), lineWidth: 1)
        )
    }

    private var manualEntryLink: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
                    phase = .manual
                }
            } label: {
                HStack(spacing: SolaceTheme.sm) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 14))
                    Text("Or build step by step")
                        .font(.inter(size: 14, weight: .medium))
                }
                .foregroundStyle(.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
        }
        .background(.appBackground)
    }

    // MARK: - Send Prompt

    private func sendPrompt() {
        let text = promptText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        workflowVM.builderError = nil
        workflowVM.buildWorkflow(prompt: text)
        isPromptFocused = false
        withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
            phase = .building
        }
    }

    // MARK: ──────────────────────────────────────────────────────────────────
    // MARK: Phase 2 — Building
    // MARK: ──────────────────────────────────────────────────────────────────

    private var buildingView: some View {
        VStack {
            Spacer()

            VStack(spacing: SolaceTheme.xl) {
                // Animated orb
                ZStack {
                    Circle()
                        .fill(Color.coral.opacity(0.05))
                        .frame(width: 140, height: 140)
                        .scaleEffect(buildPulse ? 1.3 : 0.85)
                        .opacity(buildPulse ? 0.0 : 0.5)

                    Circle()
                        .fill(Color.coral.opacity(0.08))
                        .frame(width: 100, height: 100)
                        .scaleEffect(buildPulse ? 1.1 : 0.95)

                    Circle()
                        .fill(Color.coral.opacity(0.12))
                        .frame(width: 72, height: 72)

                    Image(systemName: "gearshape.2")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.coral)
                        .rotationEffect(.degrees(gearRotation))
                }

                VStack(spacing: SolaceTheme.sm) {
                    Text("Building your workflow")
                        .font(.displaySubtitle)
                        .foregroundStyle(.textPrimary)

                    Text("Analyzing your tools and wiring the steps...")
                        .font(.caption)
                        .foregroundStyle(.textSecondary)
                }
            }

            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                buildPulse = true
            }
            withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
                gearRotation = 360
            }
        }
        .onDisappear {
            buildPulse = false
            gearRotation = 0
        }
        .onChange(of: workflowVM.isBuilding) { _, isBuilding in
            guard !isBuilding else { return }
            if workflowVM.builderResult != nil {
                withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
                    phase = .result
                }
            } else if workflowVM.builderError != nil {
                withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
                    phase = .prompt
                }
            }
        }
    }

    // MARK: ──────────────────────────────────────────────────────────────────
    // MARK: Phase 3 — Result
    // MARK: ──────────────────────────────────────────────────────────────────

    private var resultView: some View {
        ScrollView {
            if let result = workflowVM.builderResult {
                VStack(spacing: SolaceTheme.xl) {
                    Spacer().frame(height: 8)

                    // Success badge
                    VStack(spacing: SolaceTheme.md) {
                        ZStack {
                            Circle()
                                .fill(Color.success.opacity(0.1))
                                .frame(width: 56, height: 56)

                            Image(systemName: "checkmark")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.success)
                        }

                        Text("Workflow ready")
                            .font(.displaySubtitle)
                            .foregroundStyle(.textPrimary)
                    }

                    // Preview card
                    WorkflowPreviewCard(
                        name: result.name,
                        scheduleDescription: result.triggerType == "manual"
                            ? "Run on demand\(result.inputParams.map { " (\($0.count) input\($0.count == 1 ? "" : "s"))" } ?? "")"
                            : result.scheduleDescription,
                        steps: result.steps.map { step in
                            WorkflowPreviewCard.PreviewStep(
                                id: step.id,
                                name: step.name,
                                toolName: step.toolName,
                                needsConfig: step.needsConfiguration
                            )
                        },
                        needsConfiguration: result.needsConfiguration
                    )
                    .padding(.horizontal, 20)

                    // Description
                    if !result.description.isEmpty {
                        Text(result.description)
                            .font(.caption)
                            .foregroundStyle(.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                    }

                    // Warning for unconfigured steps
                    if result.needsConfiguration {
                        HStack(spacing: SolaceTheme.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.warning)
                            Text("Some steps need tools that aren't available. This workflow may fail until the required MCP servers are connected.")
                                .font(.caption)
                                .foregroundStyle(.textSecondary)
                        }
                        .padding(SolaceTheme.md)
                        .background(Color.warning.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 20)
                    }

                    // Actions
                    VStack(spacing: SolaceTheme.md) {
                        // Save — primary
                        Button {
                            workflowVM.saveBuiltWorkflow()
                            dismiss()
                        } label: {
                            HStack(spacing: SolaceTheme.sm) {
                                Image(systemName: result.needsConfiguration ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                Text(result.needsConfiguration ? "Save Anyway" : "Save Workflow")
                                    .font(.bodyMedium)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(result.needsConfiguration ? Color.warning : Color.coral)
                            .clipShape(Capsule())
                            .shadow(color: (result.needsConfiguration ? Color.warning : Color.coral).opacity(0.12), radius: 8, y: 4)
                        }

                        // Try again — secondary
                        Button {
                            workflowVM.builderResult = nil
                            workflowVM.builderError = nil
                            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                                phase = .prompt
                            }
                        } label: {
                            HStack(spacing: SolaceTheme.sm) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Try a different description")
                                    .font(.inter(size: 15, weight: .medium))
                            }
                            .foregroundStyle(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.divider, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer().frame(height: 40)
                }
            }
        }
    }

    // MARK: ──────────────────────────────────────────────────────────────────
    // MARK: Phase 4 — Manual Builder
    // MARK: ──────────────────────────────────────────────────────────────────

    private var manualView: some View {
        CardWorkflowBuilderView()
    }

    // MARK: - Manual Header

    private var manualHeader: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            // Name field — big and inviting
            TextField("Name your workflow", text: $workflowName)
                .font(.spaceGrotesk(size: 20, weight: .medium))
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, SolaceTheme.lg)
                .padding(.vertical, SolaceTheme.md)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            workflowName.isEmpty ? Color.divider : Color.coral.opacity(0.3),
                            lineWidth: 1
                        )
                )

            // Trigger + Options row
            HStack(spacing: SolaceTheme.sm) {
                // Trigger button
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        showTriggerConfig.toggle()
                        showManualOptions = false
                    }
                } label: {
                    HStack(spacing: SolaceTheme.xs) {
                        Image(systemName: triggerType == "cron" ? "clock.fill" : "hand.tap.fill")
                            .font(.system(size: 12))
                        Text(triggerType == "cron" ? "Scheduled" : "Manual")
                            .font(.inter(size: 13, weight: .medium))
                    }
                    .foregroundStyle(triggerType == "cron" ? .info : .success)
                    .padding(.horizontal, SolaceTheme.md)
                    .padding(.vertical, SolaceTheme.sm)
                    .background(
                        (triggerType == "cron" ? Color.info : Color.success).opacity(0.1)
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                showTriggerConfig
                                    ? (triggerType == "cron" ? Color.info : Color.success).opacity(0.4)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
                }

                // Options button
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        showManualOptions.toggle()
                        showTriggerConfig = false
                    }
                } label: {
                    HStack(spacing: SolaceTheme.xs) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12))
                        Text("Options")
                            .font(.inter(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.textSecondary)
                    .padding(.horizontal, SolaceTheme.md)
                    .padding(.vertical, SolaceTheme.sm)
                    .background(Color.surfaceElevated)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                showManualOptions ? Color.divider : Color.clear,
                                lineWidth: 1
                            )
                    )
                }

                Spacer()
            }

            // Expandable trigger config
            if showTriggerConfig {
                triggerConfigSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Expandable options
            if showManualOptions {
                optionsSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, SolaceTheme.lg)
        .padding(.vertical, SolaceTheme.sm)
    }

    // MARK: - Trigger Config

    private var triggerConfigSection: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            HStack(spacing: SolaceTheme.md) {
                triggerPill(type: "manual", icon: "hand.tap", label: "Manual")
                triggerPill(type: "cron", icon: "clock", label: "Schedule")
            }

            if triggerType == "cron" {
                if useRawCron {
                    TextField("*/5 * * * *", text: $cronExpression)
                        .font(.codeFont)
                        .foregroundStyle(.textPrimary)
                        .padding(SolaceTheme.sm)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.divider, lineWidth: 1)
                        )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button {
                        useRawCron = false
                    } label: {
                        Text("Use natural language")
                            .font(.small)
                            .foregroundStyle(.info)
                    }
                } else {
                    TextField("e.g. every weekday at 9am", text: $scheduleText)
                        .font(.inter(size: 14))
                        .foregroundStyle(.textPrimary)
                        .padding(SolaceTheme.sm)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.divider, lineWidth: 1)
                        )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: scheduleText) { _, newValue in
                            scheduleDebounceTask?.cancel()
                            scheduleDebounceTask = Task {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                guard !Task.isCancelled, !newValue.isEmpty else { return }
                                workflowVM.parseSchedule(text: newValue)
                            }
                        }

                    if let parsed = workflowVM.parsedSchedule {
                        HStack(spacing: SolaceTheme.xs) {
                            if parsed.success, let desc = parsed.description, let cron = parsed.cron {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.success)
                                Text("\(desc) (\(cron))")
                                    .font(.small)
                                    .foregroundStyle(.textSecondary)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.error)
                                Text(parsed.message ?? "Couldn't parse")
                                    .font(.small)
                                    .foregroundStyle(.textSecondary)
                            }
                        }
                    }

                    Button {
                        useRawCron = true
                    } label: {
                        Text("Use cron syntax")
                            .font(.small)
                            .foregroundStyle(.info)
                    }
                }
            }
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.divider, lineWidth: 1)
        )
    }

    private func triggerPill(type: String, icon: String, label: String) -> some View {
        let isSelected = triggerType == type
        return Button {
            withAnimation(.spring(duration: 0.2)) {
                triggerType = type
            }
        } label: {
            HStack(spacing: SolaceTheme.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.inter(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : .textSecondary)
            .padding(.horizontal, SolaceTheme.md)
            .padding(.vertical, SolaceTheme.sm)
            .background(isSelected ? Color.coral : Color.surfaceElevated)
            .clipShape(Capsule())
        }
    }

    // MARK: - Options Section

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.md) {
            TextField("Description (optional)", text: $workflowDescription, axis: .vertical)
                .font(.inter(size: 14))
                .foregroundStyle(.textPrimary)
                .lineLimit(2...4)
                .padding(SolaceTheme.sm)
                .background(Color.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.divider, lineWidth: 1)
                )

            VStack(spacing: SolaceTheme.sm) {
                Toggle("Notify on start", isOn: $notifyOnStart)
                Toggle("Notify on complete", isOn: $notifyOnComplete)
                Toggle("Notify on error", isOn: $notifyOnError)
                Toggle("Notify per step", isOn: $notifyOnStepComplete)
            }
            .font(.inter(size: 14))
            .foregroundStyle(.textPrimary)
            .tint(.coral)
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.divider, lineWidth: 1)
        )
    }

    // MARK: - Save Manual

    private func saveManual() {
        guard isManualValid else { return }

        let resolvedCron: String?
        if triggerType == "cron" {
            resolvedCron = useRawCron ? cronExpression : (workflowVM.parsedSchedule?.cron ?? cronExpression)
        } else {
            resolvedCron = nil
        }

        let trigger = WorkflowTriggerInfo(
            type: triggerType,
            cronExpression: resolvedCron
        )

        let steps = deckCards.enumerated().map { index, card in
            WorkflowStepInfo(
                id: card.id,
                name: card.name.isEmpty ? "Step \(index + 1)" : card.name,
                toolName: card.toolName,
                serverName: card.serverName,
                inputs: card.inputs,
                dependsOn: nil,
                onError: "stop"
            )
        }

        let detail = WorkflowDetail(
            id: UUID().uuidString,
            name: workflowName,
            description: workflowDescription,
            enabled: true,
            trigger: trigger,
            steps: steps,
            notifyOnStart: notifyOnStart,
            notifyOnComplete: notifyOnComplete,
            notifyOnError: notifyOnError,
            notifyOnStepComplete: notifyOnStepComplete
        )

        workflowVM.createWorkflow(detail)
        dismiss()
    }
}
