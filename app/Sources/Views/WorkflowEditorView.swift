import SwiftUI

struct EditableStep: Identifiable {
    let id: String
    var name: String
    var toolName: String
    var serverName: String
    var onError: String

    init(id: String = UUID().uuidString, name: String = "", toolName: String = "", serverName: String = "", onError: String = "stop") {
        self.id = id
        self.name = name
        self.toolName = toolName
        self.serverName = serverName
        self.onError = onError
    }
}

struct WorkflowEditorView: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    @Environment(\.dismiss) private var dismiss
    let existingWorkflow: WorkflowDetail?

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var triggerType: String = "cron"
    @State private var cronExpression: String = ""
    @State private var eventSource: String = ""
    @State private var eventType: String = ""
    @State private var steps: [EditableStep] = []
    @State private var notifyOnStart = false
    @State private var notifyOnComplete = true
    @State private var notifyOnError = true
    @State private var notifyOnStepComplete = false
    @State private var scheduleText: String = ""
    @State private var useRawCron: Bool = false
    @State private var scheduleDebounceTask: Task<Void, Never>?
    @State private var showToolPicker: Bool = false
    @State private var editingStepIndex: Int?

    private var isEditing: Bool { existingWorkflow != nil }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !steps.isEmpty
    }

    var body: some View {
        List {
            infoSection
            triggerSection
            stepsSection
            notificationsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationTitle(isEditing ? "Edit Workflow" : "New Workflow")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(.trust)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
                .foregroundStyle(isValid ? .heart : .trust.opacity(0.5))
                .disabled(!isValid)
                .fontWeight(.semibold)
            }
        }
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            populateFromExisting()
        }
        .sheet(isPresented: $showToolPicker) {
            ToolPickerSheet(
                tools: workflowVM.availableTools,
                isLoading: workflowVM.isLoadingTools,
                onSelect: { tool in
                    if let index = editingStepIndex, index < steps.count {
                        steps[index].toolName = tool.name
                        steps[index].serverName = tool.serverName
                        if steps[index].name.isEmpty {
                            steps[index].name = tool.description.prefix(40).description
                        }
                    }
                    showToolPicker = false
                }
            )
            .onAppear {
                workflowVM.loadMCPTools()
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            HStack {
                Text("Name")
                    .foregroundStyle(.textPrimary)
                Spacer()
                TextField("Workflow name", text: $name)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.textPrimary)
                    .autocorrectionDisabled()
            }
            .listRowBackground(Color.surface)

            VStack(alignment: .leading, spacing: LoveMeTheme.xs) {
                Text("Description")
                    .foregroundStyle(.textPrimary)

                TextField("What does this workflow do?", text: $description, axis: .vertical)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(2...4)
            }
            .listRowBackground(Color.surface)
        } header: {
            Text("INFO")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    // MARK: - Trigger Section

    private var triggerSection: some View {
        Section {
            Picker("Trigger Type", selection: $triggerType) {
                Text("Cron Schedule").tag("cron")
                Text("Event").tag("event")
            }
            .foregroundStyle(.textPrimary)
            .listRowBackground(Color.surface)

            if triggerType == "cron" {
                if useRawCron {
                    // Raw cron mode
                    HStack {
                        Text("Cron")
                            .foregroundStyle(.textPrimary)
                        Spacer()
                        TextField("*/5 * * * *", text: $cronExpression)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.textPrimary)
                            .font(.toolDetail)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .listRowBackground(Color.surface)

                    Button {
                        useRawCron = false
                    } label: {
                        Text("Use natural language")
                            .font(.timestamp)
                            .foregroundStyle(.electricBlue)
                    }
                    .listRowBackground(Color.surface)
                } else {
                    // Natural language mode
                    HStack {
                        Text("Schedule")
                            .foregroundStyle(.textPrimary)
                        Spacer()
                        TextField("e.g. every 5 minutes", text: $scheduleText)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.textPrimary)
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
                    }
                    .listRowBackground(Color.surface)

                    // Parse result feedback
                    if let parsed = workflowVM.parsedSchedule {
                        HStack(spacing: LoveMeTheme.sm) {
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
                        .listRowBackground(Color.surface)
                    }

                    Button {
                        useRawCron = true
                    } label: {
                        Text("Use cron syntax")
                            .font(.timestamp)
                            .foregroundStyle(.electricBlue)
                    }
                    .listRowBackground(Color.surface)
                }
            } else {
                HStack {
                    Text("Source")
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    TextField("e.g. github", text: $eventSource)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .listRowBackground(Color.surface)

                HStack {
                    Text("Event Type")
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    TextField("e.g. push", text: $eventType)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .listRowBackground(Color.surface)
            }
        } header: {
            Text("TRIGGER")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    // MARK: - Steps Section

    private var stepsSection: some View {
        Section {
            ForEach(Array(steps.indices), id: \.self) { index in
                stepRow(step: $steps[index], index: index)
            }
            .onDelete { indexSet in
                steps.remove(atOffsets: indexSet)
            }
            .onMove { from, to in
                steps.move(fromOffsets: from, toOffset: to)
            }

            Button {
                withAnimation(.spring(duration: LoveMeTheme.springDuration)) {
                    steps.append(EditableStep())
                }
            } label: {
                HStack(spacing: LoveMeTheme.sm) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.heart)
                    Text("Add Step")
                        .foregroundStyle(.heart)
                }
            }
            .listRowBackground(Color.surface)
        } header: {
            HStack {
                Text("STEPS")
                    .font(.sectionHeader)
                    .foregroundStyle(.trust)
                    .tracking(1.2)

                Spacer()

                Text("\(steps.count)")
                    .font(.toolDetail)
                    .foregroundStyle(.trust)
                    .padding(.horizontal, LoveMeTheme.sm)
                    .padding(.vertical, 2)
                    .background(Color.surfaceElevated)
                    .clipShape(Capsule())
            }
        }
    }

    private func stepRow(step: Binding<EditableStep>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: LoveMeTheme.sm) {
            // Step name
            HStack {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.electricBlue)
                TextField("Step name", text: step.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.textPrimary)
            }

            // Tool selection button
            Button {
                editingStepIndex = index
                showToolPicker = true
            } label: {
                HStack {
                    if step.wrappedValue.toolName.isEmpty {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(.heart)
                        Text("Choose Tool")
                            .font(.system(size: 14))
                            .foregroundStyle(.heart)
                    } else {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.electricBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.wrappedValue.toolName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.textPrimary)
                                .lineLimit(1)
                            Text(step.wrappedValue.serverName)
                                .font(.timestamp)
                                .foregroundStyle(.trust)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.trust)
                }
                .padding(LoveMeTheme.sm)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: LoveMeTheme.sm))
            }
            .buttonStyle(.plain)

            // On error behavior
            HStack {
                Text("On Error")
                    .font(.timestamp)
                    .foregroundStyle(.trust)

                Spacer()

                Picker("", selection: step.onError) {
                    Text("Stop").tag("stop")
                    Text("Skip").tag("skip")
                    Text("Retry").tag("retry")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
        .padding(.vertical, LoveMeTheme.xs)
        .listRowBackground(Color.surface)
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section {
            Toggle("On Start", isOn: $notifyOnStart)
                .foregroundStyle(.textPrimary)
                .tint(.heart)
                .listRowBackground(Color.surface)

            Toggle("On Complete", isOn: $notifyOnComplete)
                .foregroundStyle(.textPrimary)
                .tint(.heart)
                .listRowBackground(Color.surface)

            Toggle("On Error", isOn: $notifyOnError)
                .foregroundStyle(.textPrimary)
                .tint(.heart)
                .listRowBackground(Color.surface)

            Toggle("On Step Complete", isOn: $notifyOnStepComplete)
                .foregroundStyle(.textPrimary)
                .tint(.heart)
                .listRowBackground(Color.surface)
        } header: {
            Text("NOTIFICATIONS")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    // MARK: - Actions

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
            cronExpression: resolvedCron,
            eventSource: triggerType == "event" ? eventSource : nil,
            eventType: triggerType == "event" ? eventType : nil,
            eventFilter: nil
        )

        let workflowSteps = steps.enumerated().map { index, step in
            WorkflowStepInfo(
                id: step.id,
                name: step.name.isEmpty ? "Step \(index + 1)" : step.name,
                toolName: step.toolName,
                serverName: step.serverName,
                inputs: [:],
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

    private func populateFromExisting() {
        guard let existing = existingWorkflow else { return }
        name = existing.name
        description = existing.description
        triggerType = existing.trigger.type
        cronExpression = existing.trigger.cronExpression ?? ""
        eventSource = existing.trigger.eventSource ?? ""
        eventType = existing.trigger.eventType ?? ""
        notifyOnStart = existing.notifyOnStart
        notifyOnComplete = existing.notifyOnComplete
        notifyOnError = existing.notifyOnError
        notifyOnStepComplete = existing.notifyOnStepComplete

        steps = existing.steps.map { step in
            EditableStep(
                id: step.id,
                name: step.name,
                toolName: step.toolName,
                serverName: step.serverName,
                onError: step.onError
            )
        }
    }

    private var cronHint: String {
        // Simple hint for common patterns
        if cronExpression.hasPrefix("*/") {
            let parts = cronExpression.split(separator: " ")
            if let first = parts.first, first.hasPrefix("*/") {
                let interval = first.dropFirst(2)
                return "Every \(interval) minutes"
            }
        }
        return "Custom schedule"
    }
}
