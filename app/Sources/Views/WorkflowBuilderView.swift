import SwiftUI

struct WorkflowBuilderView: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    @Environment(\.dismiss) private var dismiss

    let existingWorkflow: WorkflowDetail?

    init(existingWorkflow: WorkflowDetail? = nil) {
        self.existingWorkflow = existingWorkflow
    }

    enum Phase: Equatable {
        case prompt
        case building
        case reviewEdit
        case refining
    }

    @State private var phase: Phase = .prompt

    // Prompt phase
    @State private var promptText: String = ""
    @FocusState private var isInputFocused: Bool

    // Review/Edit phase
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var triggerType: String = "manual"
    @State private var cronExpression: String = ""
    @State private var scheduleText: String = ""
    @State private var useRawCron: Bool = false
    @State private var scheduleDebounceTask: Task<Void, Never>?
    @State private var steps: [EditableStep] = []
    @State private var inputParams: [EditableInputParam] = []
    @State private var notifyOnStart = false
    @State private var notifyOnComplete = true
    @State private var notifyOnError = true
    @State private var notifyOnStepComplete = false
    @State private var showOptions = false
    @State private var expandedStepId: String?
    @State private var showTemplatePicker = false
    @State private var showToolPicker = false
    @State private var editingStepIndex: Int?

    // Refinement
    @State private var refinementText: String = ""
    @State private var showRefinementBar = false

    // Focus states
    @FocusState private var isNameFocused: Bool

    @State private var appeared = false

    private var isEditing: Bool { existingWorkflow != nil }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !steps.isEmpty
    }

    private var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespaces).isEmpty && !workflowVM.isBuilding
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .prompt:
                    promptView
                case .building:
                    buildingView
                case .reviewEdit:
                    reviewEditView
                case .refining:
                    refiningView
                }
            }
            .background(.appBackground)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.textSecondary)
                }

                if phase == .reviewEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { save() }
                            .foregroundStyle(isValid ? .heart : .textSecondary.opacity(0.5))
                            .disabled(!isValid)
                            .fontWeight(.semibold)
                    }
                }
            }
            .toolbarBackground(.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            if let existing = existingWorkflow {
                populateFromExisting(existing)
                phase = .reviewEdit
            }
            workflowVM.loadMCPTools()
            withAnimation(.easeOut(duration: 0.4)) {
                appeared = true
            }
        }
        .onChange(of: workflowVM.isBuilding) { _, isBuilding in
            if !isBuilding && phase == .building, let result = workflowVM.builderResult {
                hydrateFromResult(result)
                withAnimation(.spring(duration: 0.3)) {
                    phase = .reviewEdit
                }
            }
        }
        .onChange(of: workflowVM.isRefining) { _, isRefining in
            if !isRefining && phase == .refining, let result = workflowVM.builderResult {
                hydrateFromResult(result)
                withAnimation(.spring(duration: 0.3)) {
                    phase = .reviewEdit
                }
            }
        }
        .onChange(of: workflowVM.builderError) { _, error in
            if error != nil && phase == .building {
                phase = .prompt
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            StepTemplatePicker(
                templates: StepTemplates.merged(mcpTools: workflowVM.availableTools),
                onSelect: { template in
                    withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                        steps.append(EditableStep(
                            name: template.name,
                            toolName: template.toolName,
                            serverName: template.serverName,
                            inputs: template.defaultInputs
                        ))
                    }
                },
                onScratch: {
                    withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                        steps.append(EditableStep())
                    }
                }
            )
        }
        .sheet(isPresented: $showToolPicker) {
            ToolPickerSheet(
                tools: workflowVM.availableTools,
                isLoading: workflowVM.isLoadingTools,
                onSelect: { tool in
                    if let idx = editingStepIndex, idx < steps.count {
                        steps[idx].toolName = tool.name
                        steps[idx].serverName = tool.serverName
                    }
                }
            )
        }
    }

    private var navigationTitle: String {
        switch phase {
        case .prompt: return "Build Workflow"
        case .building: return "Building..."
        case .reviewEdit: return isEditing ? "Edit Workflow" : "Review Workflow"
        case .refining: return "Refining..."
        }
    }

    // MARK: - Phase: Prompt

    private var promptView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: SolaceTheme.lg) {
                    Spacer(minLength: 40)

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 40))
                        .foregroundStyle(.heart)

                    Text("Describe your workflow")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.textPrimary)

                    Text("Tell me what you want to automate and I'll build it for you.")
                        .font(.system(size: 15))
                        .foregroundStyle(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, SolaceTheme.xl)

                    if let error = workflowVM.builderError {
                        HStack(spacing: SolaceTheme.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.softRed)
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(.softRed)
                        }
                        .padding(SolaceTheme.md)
                        .background(Color.softRed.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(spacing: SolaceTheme.sm) {
                        exampleChip("Every 5 minutes, check for new Figma comments and post them to Slack")
                        exampleChip("Generate a 3D asset in Blender, then import it into TouchDesigner")
                        exampleChip("Monitor GitHub PRs and send a daily summary email")
                    }
                    .padding(.horizontal, SolaceTheme.lg)
                    .padding(.top, SolaceTheme.md)

                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            phase = .reviewEdit
                        }
                    } label: {
                        Text("Or build step by step")
                            .font(.system(size: 13))
                            .foregroundStyle(.electricBlue)
                    }
                    .padding(.top, SolaceTheme.sm)

                    Spacer(minLength: 60)
                }
            }

            promptInputBar
        }
    }

    private func exampleChip(_ text: String) -> some View {
        Button {
            promptText = text
            sendPrompt()
        } label: {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.electricBlue)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, SolaceTheme.md)
            .padding(.vertical, SolaceTheme.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var promptInputBar: some View {
        HStack(spacing: SolaceTheme.sm) {
            TextField("Describe your workflow...", text: $promptText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.textPrimary)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(.horizontal, SolaceTheme.md)
                .padding(.vertical, SolaceTheme.sm)
                .background(Color.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.inputFieldRadius))
                .onSubmit { sendPrompt() }

            Button { sendPrompt() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canSend ? .heart : .textSecondary.opacity(0.3))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, SolaceTheme.lg)
        .padding(.vertical, SolaceTheme.sm)
        .background(.appBackground)
    }

    // MARK: - Phase: Building / Refining

    private var buildingView: some View {
        VStack(spacing: SolaceTheme.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.coral.opacity(0.08))
                    .frame(width: 80, height: 80)
                    .scaleEffect(appeared ? 1.2 : 0.8)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: appeared)

                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.coral)
                    .rotationEffect(.degrees(appeared ? 360 : 0))
                    .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: appeared)
            }

            Text("Building your workflow...")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.textPrimary)

            Text("Analyzing tools and creating steps")
                .font(.system(size: 14))
                .foregroundStyle(.textSecondary)

            Spacer()
        }
    }

    private var refiningView: some View {
        VStack(spacing: SolaceTheme.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.electricBlue.opacity(0.08))
                    .frame(width: 80, height: 80)
                    .scaleEffect(appeared ? 1.2 : 0.8)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: appeared)

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 30))
                    .foregroundStyle(.electricBlue)
            }

            Text("Refining your workflow...")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.textPrimary)

            Text("Applying your changes")
                .font(.system(size: 14))
                .foregroundStyle(.textSecondary)

            Spacer()
        }
    }

    // MARK: - Phase: Review & Edit

    private var reviewEditView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SolaceTheme.lg) {
                    // Hero name field
                    heroNameField

                    // Trigger config
                    triggerSection

                    // Options toggle
                    optionsToggle

                    if showOptions {
                        optionsPanel
                    }

                    // Steps pipeline
                    pipelineSection

                    // Add step button
                    addStepButton
                }
                .padding(.horizontal, SolaceTheme.lg)
                .padding(.vertical, SolaceTheme.md)
            }

            // Refinement bar at bottom
            refinementBar
        }
    }

    private var heroNameField: some View {
        HStack(spacing: SolaceTheme.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.coral.opacity(isNameFocused ? 0.15 : 0.08))
                    .frame(width: 40, height: 40)

                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.coral)
            }

            TextField("Name your workflow", text: $name)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.textPrimary)
                .focused($isNameFocused)
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SolaceTheme.cardRadius)
                .strokeBorder(
                    isNameFocused ? Color.coral.opacity(0.4) : Color.divider,
                    lineWidth: isNameFocused ? 1.5 : 1
                )
        )
    }

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            Text("TRIGGER")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.textSecondary)
                .tracking(1.2)

            HStack(spacing: SolaceTheme.sm) {
                triggerPill(type: "manual", icon: "hand.tap.fill", label: "Manual", color: .sageGreen)
                triggerPill(type: "cron", icon: "clock.fill", label: "Schedule", color: .electricBlue)
            }

            if triggerType == "cron" {
                cronInput
            }

            if triggerType == "manual" && !inputParams.isEmpty {
                VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                    ForEach(Array(inputParams.indices), id: \.self) { index in
                        inputParamRow(index: index)
                    }
                }
            }

            if triggerType == "manual" {
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        inputParams.append(EditableInputParam())
                    }
                } label: {
                    HStack(spacing: SolaceTheme.sm) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("Add Input Parameter")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.electricBlue)
                }
            }
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SolaceTheme.cardRadius)
                .strokeBorder(Color.divider, lineWidth: 1)
        )
    }

    private func triggerPill(type: String, icon: String, label: String, color: Color) -> some View {
        let isSelected = triggerType == type
        return Button {
            withAnimation(.spring(duration: 0.25)) {
                triggerType = type
            }
        } label: {
            HStack(spacing: SolaceTheme.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .white : color)
            .padding(.horizontal, SolaceTheme.md)
            .padding(.vertical, 7)
            .background(isSelected ? color : color.opacity(0.1))
            .clipShape(Capsule())
        }
    }

    private var cronInput: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.xs) {
            if useRawCron {
                TextField("*/5 * * * *", text: $cronExpression)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.textPrimary)
                    .padding(SolaceTheme.sm)
                    .background(Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.xs))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button { useRawCron = false } label: {
                    Text("Use natural language")
                        .font(.system(size: 11))
                        .foregroundStyle(.electricBlue)
                }
            } else {
                TextField("e.g. every 5 minutes", text: $scheduleText)
                    .font(.system(size: 14))
                    .foregroundStyle(.textPrimary)
                    .padding(SolaceTheme.sm)
                    .background(Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.xs))
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
                    HStack(spacing: SolaceTheme.sm) {
                        if parsed.success, let desc = parsed.description, let cron = parsed.cron {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.sageGreen)
                            Text("\(desc) (\(cron))")
                                .font(.system(size: 11))
                                .foregroundStyle(.textSecondary)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.softRed)
                            Text(parsed.message ?? "Couldn't parse schedule")
                                .font(.system(size: 11))
                                .foregroundStyle(.textSecondary)
                        }
                    }
                }

                Button { useRawCron = true } label: {
                    Text("Use cron syntax")
                        .font(.system(size: 11))
                        .foregroundStyle(.electricBlue)
                }
            }
        }
    }

    private func inputParamRow(index: Int) -> some View {
        _InputParamRow(
            name: Binding<String>(
                get: { inputParams[index].name },
                set: { inputParams[index].name = $0 }
            ),
            label: Binding<String>(
                get: { inputParams[index].label },
                set: { inputParams[index].label = $0 }
            ),
            onRemove: { withAnimation { _ = inputParams.remove(at: index) } }
        )
    }

    private var optionsToggle: some View {
        Button {
            withAnimation(.spring(duration: 0.25)) {
                showOptions.toggle()
            }
        } label: {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                Text("Options")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Image(systemName: showOptions ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.textSecondary)
        }
    }

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            TextField("Description (optional)", text: $description, axis: .vertical)
                .font(.system(size: 13))
                .foregroundStyle(.textPrimary)
                .lineLimit(2...4)
                .padding(SolaceTheme.sm)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 6) {
                Toggle("Notify on start", isOn: $notifyOnStart)
                Toggle("Notify on complete", isOn: $notifyOnComplete)
                Toggle("Notify on error", isOn: $notifyOnError)
                Toggle("Notify per step", isOn: $notifyOnStepComplete)
            }
            .font(.system(size: 13))
            .foregroundStyle(.textPrimary)
            .tint(.heart)
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.divider, lineWidth: 1)
        )
    }

    // MARK: - Pipeline

    private var pipelineSection: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            HStack {
                Text("PIPELINE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.textSecondary)
                    .tracking(1.2)

                Spacer()

                if !steps.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 9))
                        Text("\(steps.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.coral)
                    .padding(.horizontal, SolaceTheme.sm)
                    .padding(.vertical, 3)
                    .background(Color.coral.opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            if steps.isEmpty {
                emptyPipeline
            } else {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    pipelineRow(index: index, step: step)
                }
            }
        }
    }

    private var emptyPipeline: some View {
        VStack(spacing: SolaceTheme.md) {
            HStack(spacing: SolaceTheme.lg) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .strokeBorder(Color.textSecondary.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text("\(i + 1)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.textSecondary.opacity(0.25))
                        )
                }
            }

            Text("Add steps below to build your pipeline")
                .font(.system(size: 13))
                .foregroundStyle(.textSecondary.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SolaceTheme.xl)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.textSecondary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }

    private func pipelineRow(index: Int, step: EditableStep) -> some View {
        let isExpanded = expandedStepId == step.id
        let (iconName, iconColor) = WorkflowStepCard.toolIcon(for: step.toolName)
        let schema = schemaForTool(step.toolName)
        let stepValid = isStepValid(step)

        return VStack(spacing: 0) {
            if index > 0 {
                connectorLine
            }

            VStack(spacing: 0) {
                // Header
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        expandedStepId = isExpanded ? nil : step.id
                    }
                } label: {
                    HStack(spacing: SolaceTheme.sm) {
                        // Step number
                        ZStack {
                            Circle()
                                .fill(iconColor.opacity(0.12))
                                .frame(width: 28, height: 28)
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(iconColor)
                        }

                        Image(systemName: iconName)
                            .font(.system(size: 13))
                            .foregroundStyle(iconColor)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.name.isEmpty ? "Step \(index + 1)" : step.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.textPrimary)
                                .lineLimit(1)

                            if !step.toolName.isEmpty {
                                HStack(spacing: 3) {
                                    Text(StepTemplates.humanizeName(step.toolName))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.textSecondary.opacity(0.6))
                                    if !step.serverName.isEmpty {
                                        Text("·")
                                            .foregroundStyle(.textSecondary.opacity(0.3))
                                        Text(step.serverName)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.textSecondary.opacity(0.4))
                                    }
                                }
                                .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 4)

                        // Validation badge
                        Image(systemName: stepValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(stepValid ? .sageGreen : .amberGlow)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.textSecondary.opacity(0.4))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Expanded content
                if isExpanded {
                    VStack(alignment: .leading, spacing: SolaceTheme.md) {
                        Divider()

                        // Step name edit
                        HStack {
                            Text("Name")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.textSecondary)
                            Spacer()
                            TextField("Step name", text: stepNameBinding(for: step.id))
                                .font(.system(size: 13))
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.textPrimary)
                        }

                        // Tool inputs (schema-driven)
                        if !schema.isEmpty {
                            StepInputEditor(step: stepBinding(for: step.id), schema: schema)
                        } else if !step.inputs.isEmpty {
                            // Fallback: show raw key-value inputs
                            ForEach(Array(step.inputs.keys.sorted()), id: \.self) { key in
                                HStack {
                                    Text(key)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.electricBlue)
                                    Spacer()
                                    TextField("value", text: stepInputBinding(for: step.id, key: key))
                                        .font(.system(size: 12))
                                        .multilineTextAlignment(.trailing)
                                        .foregroundStyle(.textPrimary)
                                }
                            }
                        }

                        // On-error picker
                        HStack {
                            Text("On Error")
                                .font(.system(size: 12))
                                .foregroundStyle(.textSecondary)
                            Spacer()
                            Picker("", selection: stepOnErrorBinding(for: step.id)) {
                                Text("Stop").tag("stop")
                                Text("Skip").tag("skip")
                                Text("Retry").tag("retry")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }

                        // Change tool button
                        Button {
                            editingStepIndex = index
                            showToolPicker = true
                        } label: {
                            HStack(spacing: SolaceTheme.sm) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11))
                                Text("Change Tool")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(.electricBlue)
                        }
                    }
                    .padding(.top, SolaceTheme.sm)
                }
            }
            .padding(.horizontal, SolaceTheme.md)
            .padding(.vertical, SolaceTheme.sm)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(iconColor.opacity(0.4))
                    .frame(width: 3)
                    .padding(.vertical, SolaceTheme.xs)
            }
            .contextMenu {
                Button(role: .destructive) {
                    withAnimation { removeStep(at: index) }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                if index > 0 {
                    Button {
                        withAnimation { moveStep(from: index, to: index - 1) }
                    } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                }
                if index < steps.count - 1 {
                    Button {
                        withAnimation { moveStep(from: index, to: index + 1) }
                    } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.85).combined(with: .opacity),
                removal: .scale(scale: 0.85).combined(with: .opacity)
            ))
        }
    }

    private var connectorLine: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.coral.opacity(0.2))
                .frame(width: 2, height: 8)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.coral.opacity(0.3))
            Rectangle()
                .fill(Color.coral.opacity(0.2))
                .frame(width: 2, height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var addStepButton: some View {
        Button {
            showTemplatePicker = true
        } label: {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                Text("Add Step")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.heart)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SolaceTheme.md)
            .background(Color.heart.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.heart.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Refinement Bar

    private var refinementBar: some View {
        VStack(spacing: 0) {
            Divider()

            if showRefinementBar {
                HStack(spacing: SolaceTheme.sm) {
                    TextField("Refine with AI...", text: $refinementText, axis: .vertical)
                        .font(.system(size: 14))
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1...3)
                        .padding(.horizontal, SolaceTheme.md)
                        .padding(.vertical, SolaceTheme.sm)
                        .background(Color.inputBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Button {
                        guard !refinementText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        // Need a saved workflow ID to refine; save first if needed
                        if let wfId = existingWorkflow?.id ?? workflowVM.builderResult?.id {
                            workflowVM.refineWorkflow(workflowId: wfId, refinementPrompt: refinementText)
                            refinementText = ""
                            withAnimation { phase = .refining }
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.electricBlue)
                    }
                }
                .padding(.horizontal, SolaceTheme.lg)
                .padding(.vertical, SolaceTheme.sm)
            } else {
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        showRefinementBar = true
                    }
                } label: {
                    HStack(spacing: SolaceTheme.sm) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12))
                        Text("Refine with AI")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.electricBlue)
                    .padding(.vertical, SolaceTheme.sm)
                }
            }
        }
        .background(.appBackground)
    }

    // MARK: - Helpers

    private func sendPrompt() {
        guard canSend else { return }
        workflowVM.buildWorkflow(prompt: promptText)
        withAnimation(.spring(duration: 0.3)) {
            phase = .building
        }
    }

    private func hydrateFromResult(_ result: BuilderWorkflowResult) {
        name = result.name
        description = result.description
        triggerType = result.triggerType

        if triggerType == "cron" {
            cronExpression = result.cronExpression
            if !result.scheduleDescription.isEmpty {
                scheduleText = result.scheduleDescription
            }
            useRawCron = true
        }

        if let params = result.inputParams {
            inputParams = params.map {
                EditableInputParam(name: $0.name, label: $0.label, placeholder: $0.placeholder ?? "")
            }
        }

        steps = result.steps.map { step in
            EditableStep(
                id: step.id,
                name: step.name,
                toolName: step.toolName,
                serverName: step.serverName,
                onError: "stop",
                inputs: step.inputs
            )
        }
    }

    private func populateFromExisting(_ existing: WorkflowDetail) {
        name = existing.name
        description = existing.description
        triggerType = existing.trigger.type
        cronExpression = existing.trigger.cronExpression ?? ""
        notifyOnStart = existing.notifyOnStart
        notifyOnComplete = existing.notifyOnComplete
        notifyOnError = existing.notifyOnError
        notifyOnStepComplete = existing.notifyOnStepComplete

        if existing.trigger.cronExpression != nil {
            useRawCron = true
        }

        steps = existing.steps.map { step in
            EditableStep(
                id: step.id,
                name: step.name,
                toolName: step.toolName,
                serverName: step.serverName,
                onError: step.onError,
                inputs: step.inputs
            )
        }

        if let params = existing.trigger.inputParams {
            inputParams = params.map {
                EditableInputParam(name: $0.name, label: $0.label, placeholder: $0.placeholder ?? "")
            }
        }

        if !description.isEmpty || notifyOnStart || !notifyOnComplete || !notifyOnError || notifyOnStepComplete {
            showOptions = true
        }
    }

    private func save() {
        let resolvedCron: String?
        if triggerType == "cron" {
            resolvedCron = useRawCron ? cronExpression : (workflowVM.parsedSchedule?.cron ?? cronExpression)
        } else {
            resolvedCron = nil
        }

        let resolvedInputParams: [InputParamInfo]?
        if triggerType == "manual" && !inputParams.isEmpty {
            resolvedInputParams = inputParams.filter { !$0.name.isEmpty }.map {
                InputParamInfo(name: $0.name, label: $0.label.isEmpty ? $0.name : $0.label, placeholder: $0.placeholder.isEmpty ? nil : $0.placeholder)
            }
        } else {
            resolvedInputParams = nil
        }

        let trigger = WorkflowTriggerInfo(
            type: triggerType,
            cronExpression: resolvedCron,
            inputParams: resolvedInputParams
        )

        let workflowSteps = steps.enumerated().map { index, step in
            WorkflowStepInfo(
                id: step.id,
                name: step.name.isEmpty ? "Step \(index + 1)" : step.name,
                toolName: step.toolName,
                serverName: step.serverName,
                inputs: step.inputs,
                dependsOn: nil,
                onError: step.onError
            )
        }

        let detail = WorkflowDetail(
            id: existingWorkflow?.id ?? UUID().uuidString,
            name: name,
            description: description,
            enabled: existingWorkflow?.enabled ?? true,
            trigger: trigger,
            steps: workflowSteps,
            notifyOnStart: notifyOnStart,
            notifyOnComplete: notifyOnComplete,
            notifyOnError: notifyOnError,
            notifyOnStepComplete: notifyOnStepComplete
        )

        if isEditing {
            workflowVM.updateWorkflow(detail)
        } else {
            workflowVM.createWorkflow(detail)
        }
        dismiss()
    }

    private func removeStep(at index: Int) {
        if expandedStepId == steps[index].id {
            expandedStepId = nil
        }
        steps.remove(at: index)
    }

    private func moveStep(from: Int, to: Int) {
        steps.swapAt(from, to)
    }

    private func schemaForTool(_ toolName: String) -> [SchemaProperty] {
        workflowVM.availableTools.first(where: { $0.name == toolName })?.schemaProperties ?? []
    }

    private func isStepValid(_ step: EditableStep) -> Bool {
        guard !step.toolName.isEmpty else { return false }
        let schema = schemaForTool(step.toolName)
        let requiredProps = schema.filter(\.isRequired)
        for prop in requiredProps {
            if step.inputs[prop.name]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
                return false
            }
        }
        return true
    }

    // MARK: - Bindings

    private func stepBinding(for id: String) -> Binding<EditableStep> {
        Binding(
            get: { steps.first(where: { $0.id == id }) ?? EditableStep() },
            set: { newValue in
                if let idx = steps.firstIndex(where: { $0.id == id }) {
                    steps[idx] = newValue
                }
            }
        )
    }

    private func stepNameBinding(for id: String) -> Binding<String> {
        Binding(
            get: { steps.first(where: { $0.id == id })?.name ?? "" },
            set: { newValue in
                if let idx = steps.firstIndex(where: { $0.id == id }) {
                    steps[idx].name = newValue
                }
            }
        )
    }

    private func stepOnErrorBinding(for id: String) -> Binding<String> {
        Binding(
            get: { steps.first(where: { $0.id == id })?.onError ?? "stop" },
            set: { newValue in
                if let idx = steps.firstIndex(where: { $0.id == id }) {
                    steps[idx].onError = newValue
                }
            }
        )
    }

    private func stepInputBinding(for id: String, key: String) -> Binding<String> {
        Binding(
            get: { steps.first(where: { $0.id == id })?.inputs[key] ?? "" },
            set: { newValue in
                if let idx = steps.firstIndex(where: { $0.id == id }) {
                    steps[idx].inputs[key] = newValue
                }
            }
        )
    }
}

// MARK: - Extracted Sub-Views (Type Checker Relief)

private struct _InputParamRow: View {
    @Binding var name: String
    @Binding var label: String
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.xs) {
            HStack {
                Image(systemName: "text.cursor")
                    .font(.system(size: 12))
                    .foregroundStyle(.electricBlue)
                TextField("param_name", text: $name)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.textSecondary.opacity(0.5))
                }
            }
            TextField("Label (e.g. Figma URL)", text: $label)
                .font(.system(size: 12))
                .foregroundStyle(.textSecondary)
        }
        .padding(SolaceTheme.sm)
        .background(Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
