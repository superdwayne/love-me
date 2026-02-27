import SwiftUI

// MARK: - Shimmer Modifier

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 300
                }
            }
    }
}

private extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Display Model

struct TriggerRuleDisplay: Identifiable {
    let id: String
    var workflowId: String
    var workflowName: String
    var fromContains: String
    var subjectContains: String
    var bodyContains: String
    var hasAttachment: Bool
    var enabled: Bool

    /// Returns a human-readable summary of the rule's conditions.
    var conditionsSummary: String {
        var parts: [String] = []
        if !fromContains.isEmpty {
            parts.append("From: \(fromContains)")
        }
        if !subjectContains.isEmpty {
            parts.append("Subject: \(subjectContains)")
        }
        if !bodyContains.isEmpty {
            parts.append("Body: \(bodyContains)")
        }
        if hasAttachment {
            parts.append("Has attachment")
        }
        return parts.isEmpty ? "No conditions" : parts.joined(separator: " · ")
    }

    static func empty() -> TriggerRuleDisplay {
        TriggerRuleDisplay(
            id: UUID().uuidString,
            workflowId: "",
            workflowName: "",
            fromContains: "",
            subjectContains: "",
            bodyContains: "",
            hasAttachment: false,
            enabled: true
        )
    }
}

// MARK: - View

struct EmailTriggersView: View {
    @Environment(WebSocketClient.self) private var webSocket
    @Environment(WorkflowViewModel.self) private var workflowVM

    @State private var rules: [TriggerRuleDisplay] = []
    @State private var showAddSheet = false
    @State private var editingRule: TriggerRuleDisplay?
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading && rules.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    skeletonRow
                }
                .listRowBackground(Color.surface)
            } else if rules.isEmpty {
                emptyState
                    .listRowBackground(Color.appBackground)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(rules) { rule in
                    ruleRow(rule)
                        .listRowBackground(Color.surface)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteRule(rule)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingRule = rule
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationTitle("Email Rules")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: LoveMeTheme.springDuration), value: rules.count)
        .animation(.easeInOut(duration: LoveMeTheme.springDuration), value: isLoading)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                    HapticManager.messageSent()
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.heart)
                        .frame(minWidth: LoveMeTheme.minTouchTarget,
                               minHeight: LoveMeTheme.minTouchTarget)
                }
                .accessibilityLabel("Add email rule")
            }
        }
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                TriggerRuleFormView(
                    rule: .empty(),
                    workflows: workflowVM.workflows,
                    isNew: true
                ) { newRule in
                    createRule(newRule)
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            NavigationStack {
                TriggerRuleFormView(
                    rule: rule,
                    workflows: workflowVM.workflows,
                    isNew: false
                ) { updatedRule in
                    updateRule(updatedRule)
                }
            }
        }
        .onAppear {
            loadRules()
            workflowVM.loadWorkflows()
        }
    }

    // MARK: - Subviews

    private func ruleRow(_ rule: TriggerRuleDisplay) -> some View {
        HStack(spacing: LoveMeTheme.lg) {
            // Left accent indicator
            RoundedRectangle(cornerRadius: 1.5)
                .fill(rule.enabled ? Color.sageGreen : Color.trust.opacity(0.3))
                .frame(width: LoveMeTheme.toolCardLeftBorderWidth)

            VStack(alignment: .leading, spacing: LoveMeTheme.xs) {
                HStack(spacing: LoveMeTheme.sm) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.toolTitle)
                        .foregroundStyle(.trust)

                    Text(rule.workflowName.isEmpty ? "No workflow" : rule.workflowName)
                        .font(.chatMessage)
                        .fontWeight(.medium)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                }

                Text(rule.conditionsSummary)
                    .font(.toolDetail)
                    .foregroundStyle(.trust)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { newValue in
                    toggleRule(rule, enabled: newValue)
                }
            ))
            .labelsHidden()
            .tint(.sageGreen)
            .accessibilityLabel("\(rule.workflowName) toggle")
            .accessibilityValue(rule.enabled ? "Enabled" : "Disabled")
        }
        .padding(.vertical, LoveMeTheme.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.workflowName) rule, \(rule.conditionsSummary), \(rule.enabled ? "enabled" : "disabled")")
    }

    private var emptyState: some View {
        VStack(spacing: LoveMeTheme.lg) {
            Spacer()
                .frame(height: 80)

            Image(systemName: "envelope.open")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.trust.opacity(0.4))

            VStack(spacing: LoveMeTheme.sm) {
                Text("No email rules yet")
                    .font(.emptyStateTitle)
                    .foregroundStyle(.textPrimary)

                Text("Create a rule to automatically run workflows\nwhen specific emails arrive.")
                    .font(.chatMessage)
                    .foregroundStyle(.trust)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: LoveMeTheme.sm) {
                    Image(systemName: "plus")
                    Text("Create Rule")
                }
                .font(.toolTitle)
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, LoveMeTheme.xl)
                .padding(.vertical, LoveMeTheme.md)
                .background(
                    RoundedRectangle(cornerRadius: LoveMeTheme.inputFieldRadius)
                        .stroke(Color.trust.opacity(0.3), lineWidth: 1)
                )
            }
            .padding(.top, LoveMeTheme.sm)
            .accessibilityLabel("Create first email rule")

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var skeletonRow: some View {
        HStack(spacing: LoveMeTheme.lg) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.surfaceElevated.opacity(0.4))
                .frame(width: LoveMeTheme.toolCardLeftBorderWidth)

            VStack(alignment: .leading, spacing: LoveMeTheme.sm) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.surfaceElevated)
                    .frame(width: 160, height: 16)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.surfaceElevated.opacity(0.6))
                    .frame(width: 220, height: 12)
            }

            Spacer()
        }
        .padding(.vertical, LoveMeTheme.sm)
        .shimmer()
    }

    // MARK: - Actions

    private func loadRules() {
        isLoading = true
        webSocket.send(WSMessage(type: WSMessageType.emailTriggersList))
    }

    private func createRule(_ rule: TriggerRuleDisplay) {
        webSocket.send(WSMessage(
            type: WSMessageType.emailTriggerCreate,
            metadata: encodeRule(rule)
        ))
        rules.append(rule)
        HapticManager.toolCompleted()
    }

    private func updateRule(_ rule: TriggerRuleDisplay) {
        webSocket.send(WSMessage(
            type: WSMessageType.emailTriggerUpdate,
            metadata: encodeRule(rule)
        ))
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        }
        HapticManager.toolCompleted()
    }

    private func deleteRule(_ rule: TriggerRuleDisplay) {
        webSocket.send(WSMessage(
            type: WSMessageType.emailTriggerDelete,
            id: rule.id
        ))
        withAnimation(.easeInOut(duration: LoveMeTheme.springDuration)) {
            rules.removeAll { $0.id == rule.id }
        }
        HapticManager.toolError()
    }

    private func toggleRule(_ rule: TriggerRuleDisplay, enabled: Bool) {
        var updated = rule
        updated.enabled = enabled
        updateRule(updated)
    }

    private func encodeRule(_ rule: TriggerRuleDisplay) -> [String: MetadataValue] {
        [
            "id": .string(rule.id),
            "workflowId": .string(rule.workflowId),
            "fromContains": .string(rule.fromContains),
            "subjectContains": .string(rule.subjectContains),
            "bodyContains": .string(rule.bodyContains),
            "hasAttachment": .bool(rule.hasAttachment),
            "enabled": .bool(rule.enabled),
        ]
    }

    // MARK: - Message Handling

    /// Called by the app's message router when trigger list responses arrive.
    func handleTriggersList(_ msg: WSMessage) {
        isLoading = false
        guard case .array(let items) = msg.metadata?["rules"] else { return }

        var loaded: [TriggerRuleDisplay] = []
        for item in items {
            guard case .object(let dict) = item else { continue }
            guard let id = dict["id"]?.stringValue else { continue }

            loaded.append(TriggerRuleDisplay(
                id: id,
                workflowId: dict["workflowId"]?.stringValue ?? "",
                workflowName: dict["workflowName"]?.stringValue ?? "",
                fromContains: dict["fromContains"]?.stringValue ?? "",
                subjectContains: dict["subjectContains"]?.stringValue ?? "",
                bodyContains: dict["bodyContains"]?.stringValue ?? "",
                hasAttachment: dict["hasAttachment"]?.boolValue ?? false,
                enabled: dict["enabled"]?.boolValue ?? true
            ))
        }

        rules = loaded
    }
}

// MARK: - Trigger Rule Form

struct TriggerRuleFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var rule: TriggerRuleDisplay
    private let workflows: [WorkflowItem]
    private let isNew: Bool
    private let onSave: (TriggerRuleDisplay) -> Void

    init(rule: TriggerRuleDisplay, workflows: [WorkflowItem], isNew: Bool, onSave: @escaping (TriggerRuleDisplay) -> Void) {
        self._rule = State(initialValue: rule)
        self.workflows = workflows
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        List {
            conditionsSection
            attachmentSection
            workflowSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationTitle(isNew ? "New Rule" : "Edit Rule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
                .font(.chatMessage)
                .foregroundStyle(.trust)
                .accessibilityLabel("Cancel editing rule")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    HapticManager.toolCompleted()
                    onSave(rule)
                    dismiss()
                }
                .font(.chatMessage)
                .fontWeight(.semibold)
                .foregroundStyle(.heart)
                .disabled(rule.workflowId.isEmpty)
                .accessibilityLabel("Save rule")
            }
        }
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Sections

    private var conditionsSection: some View {
        Section {
            conditionField(
                icon: "person.fill",
                label: "From",
                placeholder: "e.g. boss@company.com",
                text: $rule.fromContains,
                keyboard: .emailAddress
            )

            conditionField(
                icon: "text.justify.leading",
                label: "Subject",
                placeholder: "e.g. urgent",
                text: $rule.subjectContains
            )

            conditionField(
                icon: "doc.text.fill",
                label: "Body",
                placeholder: "e.g. action required",
                text: $rule.bodyContains
            )
        } header: {
            Text("CONDITIONS")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        } footer: {
            Text("Leave a field empty to match all values. Multiple conditions are combined with AND.")
                .font(.toolDetail)
                .foregroundStyle(.trust)
                .padding(.top, LoveMeTheme.xs)
        }
    }

    private func conditionField(
        icon: String,
        label: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: LoveMeTheme.md) {
            Image(systemName: icon)
                .font(.toolTitle)
                .foregroundStyle(.trust)
                .frame(width: 20)
            Text(label)
                .font(.chatMessage)
                .foregroundStyle(.textPrimary)
                .frame(width: 64, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.chatMessage)
                .foregroundStyle(.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(keyboard)
        }
        .frame(minHeight: LoveMeTheme.minTouchTarget)
        .listRowBackground(Color.surface)
        .accessibilityLabel("\(label) contains")
    }

    private var attachmentSection: some View {
        Section {
            Toggle(isOn: $rule.hasAttachment) {
                HStack(spacing: LoveMeTheme.md) {
                    Image(systemName: "paperclip")
                        .font(.toolTitle)
                        .foregroundStyle(.trust)
                        .frame(width: 20)
                    Text("Has Attachment")
                        .font(.chatMessage)
                        .foregroundStyle(.textPrimary)
                }
            }
            .tint(.sageGreen)
            .frame(minHeight: LoveMeTheme.minTouchTarget)
            .listRowBackground(Color.surface)
            .accessibilityLabel("Require attachment")
            .accessibilityValue(rule.hasAttachment ? "Required" : "Not required")
        } header: {
            Text("ATTACHMENT")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        }
    }

    private var workflowSection: some View {
        Section {
            if workflows.isEmpty {
                HStack(spacing: LoveMeTheme.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.toolTitle)
                        .foregroundStyle(.amberGlow)
                    Text("No workflows available")
                        .font(.chatMessage)
                        .foregroundStyle(.trust)
                }
                .frame(minHeight: LoveMeTheme.minTouchTarget)
                .listRowBackground(Color.surface)
            } else {
                Picker(selection: $rule.workflowId) {
                    Text("Select a workflow")
                        .tag("")

                    ForEach(workflows) { workflow in
                        Text(workflow.name)
                            .tag(workflow.id)
                    }
                } label: {
                    HStack(spacing: LoveMeTheme.md) {
                        Image(systemName: "bolt.fill")
                            .font(.toolTitle)
                            .foregroundStyle(.trust)
                            .frame(width: 20)
                        Text("Workflow")
                            .font(.chatMessage)
                            .foregroundStyle(.textPrimary)
                    }
                }
                .tint(.trust)
                .frame(minHeight: LoveMeTheme.minTouchTarget)
                .listRowBackground(Color.surface)
                .accessibilityLabel("Select workflow")
                .onChange(of: rule.workflowId) { _, newId in
                    if let workflow = workflows.first(where: { $0.id == newId }) {
                        rule.workflowName = workflow.name
                    }
                }
            }
        } header: {
            Text("WORKFLOW")
                .font(.sectionHeader)
                .foregroundStyle(.trust)
                .tracking(1.2)
        } footer: {
            Text("The workflow to run when an email matches these conditions.")
                .font(.toolDetail)
                .foregroundStyle(.trust)
                .padding(.top, LoveMeTheme.xs)
        }
    }
}
