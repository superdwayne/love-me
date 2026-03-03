import SwiftUI

struct CardWorkflowBuilderView: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    @Environment(\.dismiss) private var dismiss

    // Workflow metadata
    @State private var name = ""
    @State private var description = ""
    @State private var triggerType = "manual"
    @State private var cronExpression = ""
    @State private var scheduleText = ""
    @State private var useRawCron = false
    @State private var scheduleDebounceTask: Task<Void, Never>?

    // Pipeline steps
    @State private var steps: [EditableStep] = []

    // Notifications
    @State private var notifyOnStart = false
    @State private var notifyOnComplete = true
    @State private var notifyOnError = true
    @State private var notifyOnStepComplete = false

    // UI state
    @State private var selectedCategory: StepTemplateCategory?
    @State private var searchText = ""
    @State private var showOptions = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !steps.isEmpty
    }

    private var allTemplates: [StepTemplate] {
        StepTemplates.merged(mcpTools: workflowVM.availableTools)
    }

    private var filteredTemplates: [StepTemplate] {
        var result = allTemplates
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.description.lowercased().contains(query) ||
                $0.toolName.lowercased().contains(query)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top: Pipeline area
            pipelineSection

            Divider().background(.divider)

            // Bottom: Template card grid
            templateGridSection
        }
        .background(.appBackground)
        .navigationTitle("Build Workflow")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.trust)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .foregroundStyle(isValid ? .heart : .trust.opacity(0.5))
                    .disabled(!isValid)
                    .fontWeight(.semibold)
            }
        }
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            workflowVM.loadMCPTools()
        }
    }

    // MARK: - Pipeline Section (Top Half)

    private var pipelineSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SolaceTheme.lg) {
                // Name field
                VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                    Text("NAME")
                        .font(.sectionHeader)
                        .foregroundStyle(.trust)
                        .tracking(1.2)

                    TextField("Workflow name", text: $name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.textPrimary)
                        .padding(SolaceTheme.md)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
                }

                // Trigger picker
                VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                    Text("TRIGGER")
                        .font(.sectionHeader)
                        .foregroundStyle(.trust)
                        .tracking(1.2)

                    Picker("", selection: $triggerType) {
                        Text("Manual").tag("manual")
                        Text("Schedule").tag("cron")
                    }
                    .pickerStyle(.segmented)

                    if triggerType == "cron" {
                        cronInput
                    }
                }

                // Step pipeline
                VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                    HStack {
                        Text("PIPELINE")
                            .font(.sectionHeader)
                            .foregroundStyle(.trust)
                            .tracking(1.2)

                        Spacer()

                        if !steps.isEmpty {
                            Text("\(steps.count) step\(steps.count == 1 ? "" : "s")")
                                .font(.toolDetail)
                                .foregroundStyle(.trust)
                                .padding(.horizontal, SolaceTheme.sm)
                                .padding(.vertical, 2)
                                .background(Color.surfaceElevated)
                                .clipShape(Capsule())
                        }
                    }

                    if steps.isEmpty {
                        emptyPipeline
                    } else {
                        pipelineSteps
                    }
                }

                // Options
                DisclosureGroup("Options", isExpanded: $showOptions) {
                    VStack(spacing: SolaceTheme.sm) {
                        // Description
                        VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                            Text("Description")
                                .font(.timestamp)
                                .foregroundStyle(.trust)
                            TextField("What does this workflow do?", text: $description, axis: .vertical)
                                .font(.system(size: 14))
                                .foregroundStyle(.textPrimary)
                                .lineLimit(2...4)
                                .padding(SolaceTheme.sm)
                                .background(Color.surface)
                                .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.xs))
                        }

                        Toggle("Notify on start", isOn: $notifyOnStart)
                            .font(.system(size: 14))
                            .foregroundStyle(.textPrimary)
                            .tint(.heart)
                        Toggle("Notify on complete", isOn: $notifyOnComplete)
                            .font(.system(size: 14))
                            .foregroundStyle(.textPrimary)
                            .tint(.heart)
                        Toggle("Notify on error", isOn: $notifyOnError)
                            .font(.system(size: 14))
                            .foregroundStyle(.textPrimary)
                            .tint(.heart)
                        Toggle("Notify per step", isOn: $notifyOnStepComplete)
                            .font(.system(size: 14))
                            .foregroundStyle(.textPrimary)
                            .tint(.heart)
                    }
                    .padding(.top, SolaceTheme.sm)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.trust)
            }
            .padding(SolaceTheme.lg)
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
    }

    // MARK: - Cron Input

    private var cronInput: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.xs) {
            if useRawCron {
                TextField("*/5 * * * *", text: $cronExpression)
                    .font(.toolDetail)
                    .foregroundStyle(.textPrimary)
                    .padding(SolaceTheme.sm)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.xs))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    useRawCron = false
                } label: {
                    Text("Use natural language")
                        .font(.timestamp)
                        .foregroundStyle(.electricBlue)
                }
            } else {
                TextField("e.g. every 5 minutes", text: $scheduleText)
                    .font(.system(size: 14))
                    .foregroundStyle(.textPrimary)
                    .padding(SolaceTheme.sm)
                    .background(Color.surface)
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
                                .font(.toolDetail)
                                .foregroundStyle(.trust)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.softRed)
                            Text(parsed.message ?? "Couldn't parse schedule")
                                .font(.toolDetail)
                                .foregroundStyle(.trust)
                        }
                    }
                }

                Button {
                    useRawCron = true
                } label: {
                    Text("Use cron syntax")
                        .font(.timestamp)
                        .foregroundStyle(.electricBlue)
                }
            }
        }
    }

    // MARK: - Empty Pipeline

    private var emptyPipeline: some View {
        VStack(spacing: SolaceTheme.sm) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 24))
                .foregroundStyle(.trust.opacity(0.4))
            Text("Tap cards below to add steps")
                .font(.system(size: 13))
                .foregroundStyle(.trust.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SolaceTheme.xl)
        .background(Color.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
    }

    // MARK: - Pipeline Steps

    private var pipelineSteps: some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                pipelineRow(index: index, step: step)
            }
        }
    }

    private func pipelineRow(index: Int, step: EditableStep) -> some View {
        VStack(spacing: 0) {
            if index > 0 {
                connectorLine
            }

            WorkflowStepCard(
                mode: .preview,
                index: index,
                name: step.name,
                toolName: step.toolName,
                serverName: step.serverName,
                inputs: step.inputs,
                needsConfig: step.toolName.isEmpty
            )
            .contextMenu {
                Button(role: .destructive) {
                    removeStep(at: index)
                } label: {
                    Label("Remove", systemImage: "trash")
                }

                if index > 0 {
                    Button {
                        moveStep(from: index, to: index - 1)
                    } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                }

                if index < steps.count - 1 {
                    Button {
                        moveStep(from: index, to: index + 1)
                    } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .scale(scale: 0.8).combined(with: .opacity)
            ))
        }
    }

    private var connectorLine: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.trust.opacity(0.2))
                .frame(width: 2, height: 12)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.trust.opacity(0.3))
            Rectangle()
                .fill(Color.trust.opacity(0.2))
                .frame(width: 2, height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Template Grid Section (Bottom Half)

    private var templateGridSection: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.trust)
                TextField("Search steps...", text: $searchText)
                    .font(.system(size: 14))
                    .foregroundStyle(.textPrimary)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.trust)
                    }
                }
            }
            .padding(SolaceTheme.sm)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
            .padding(.horizontal, SolaceTheme.lg)
            .padding(.top, SolaceTheme.md)

            // Category filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SolaceTheme.sm) {
                    categoryChip(nil, label: "All")
                    ForEach(StepTemplateCategory.allCases) { category in
                        categoryChip(category, label: category.rawValue)
                    }
                }
                .padding(.horizontal, SolaceTheme.lg)
                .padding(.vertical, SolaceTheme.sm)
            }

            // Template grid
            if workflowVM.isLoadingTools {
                ProgressView()
                    .tint(.heart)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredTemplates.isEmpty {
                VStack(spacing: SolaceTheme.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(.trust.opacity(0.4))
                    Text("No matching steps")
                        .font(.system(size: 13))
                        .foregroundStyle(.trust)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: SolaceTheme.sm),
                        GridItem(.flexible(), spacing: SolaceTheme.sm)
                    ], spacing: SolaceTheme.sm) {
                        ForEach(filteredTemplates) { template in
                            templateCard(template)
                        }
                    }
                    .padding(.horizontal, SolaceTheme.lg)
                    .padding(.bottom, SolaceTheme.xl)
                }
            }
        }
    }

    // MARK: - Template Card

    private func templateCard(_ template: StepTemplate) -> some View {
        Button {
            withAnimation(.spring(duration: SolaceTheme.springDuration, bounce: 0.2)) {
                steps.append(EditableStep(
                    name: template.name,
                    toolName: template.toolName,
                    serverName: template.serverName,
                    inputs: template.defaultInputs
                ))
            }
            HapticManager.stepStarted()
        } label: {
            VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                // Icon
                Circle()
                    .fill(template.iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: template.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(template.iconColor)
                    }

                // Name
                Text(template.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)

                // Description
                Text(template.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.trust)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Server badge
                if !template.serverName.isEmpty {
                    Text(template.serverName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.electricBlue)
                        .padding(.horizontal, SolaceTheme.sm)
                        .padding(.vertical, 2)
                        .background(Color.electricBlue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SolaceTheme.md)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
            .overlay(
                RoundedRectangle(cornerRadius: SolaceTheme.sm)
                    .strokeBorder(Color.trust.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Chip

    private func categoryChip(_ category: StepTemplateCategory?, label: String) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.spring(duration: 0.2)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: SolaceTheme.xs) {
                if let cat = category {
                    Image(systemName: cat.icon)
                        .font(.system(size: 10))
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : .trust)
            .padding(.horizontal, SolaceTheme.md)
            .padding(.vertical, SolaceTheme.sm)
            .background(isSelected ? Color.heart : Color.surfaceElevated)
            .clipShape(Capsule())
        }
    }

    // MARK: - Step Mutations

    private func removeStep(at index: Int) {
        withAnimation(.spring(duration: SolaceTheme.springDuration)) {
            _ = steps.remove(at: index)
        }
    }

    private func moveStep(from source: Int, to destination: Int) {
        withAnimation(.spring(duration: SolaceTheme.springDuration)) {
            let step = steps.remove(at: source)
            steps.insert(step, at: destination)
        }
    }

    // MARK: - Save

    private func save() {
        let resolvedCron: String?
        if triggerType == "cron" {
            if useRawCron {
                resolvedCron = cronExpression
            } else {
                resolvedCron = workflowVM.parsedSchedule?.cron ?? cronExpression
            }
        } else {
            resolvedCron = nil
        }

        let trigger = WorkflowTriggerInfo(
            type: triggerType,
            cronExpression: resolvedCron
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
            id: UUID().uuidString,
            name: name,
            description: description,
            enabled: true,
            trigger: trigger,
            steps: workflowSteps,
            notifyOnStart: notifyOnStart,
            notifyOnComplete: notifyOnComplete,
            notifyOnError: notifyOnError,
            notifyOnStepComplete: notifyOnStepComplete
        )

        workflowVM.createWorkflow(detail)
        dismiss()
    }
}
