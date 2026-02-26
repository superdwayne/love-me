import SwiftUI

struct WorkflowBuilderView: View {
    @Environment(WorkflowViewModel.self) private var workflowVM
    @Environment(\.dismiss) private var dismiss
    @State private var promptText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            ScrollView {
                VStack(spacing: LoveMeTheme.lg) {
                    // Instructions
                    if workflowVM.builderResult == nil && !workflowVM.isBuilding {
                        onboardingSection
                    }

                    // Loading state
                    if workflowVM.isBuilding {
                        buildingIndicator
                    }

                    // Error
                    if let error = workflowVM.builderError {
                        errorBanner(error)
                    }

                    // Result preview
                    if let result = workflowVM.builderResult {
                        resultSection(result)
                    }
                }
                .padding(LoveMeTheme.lg)
            }

            Divider()
                .foregroundStyle(.divider)

            // Input bar
            inputBar
        }
        .background(.appBackground)
        .navigationTitle("Build with AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.trust)
            }
        }
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Onboarding

    private var onboardingSection: some View {
        VStack(spacing: LoveMeTheme.md) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 40))
                .foregroundStyle(.heart)
                .padding(.top, LoveMeTheme.xxl)

            Text("Describe your workflow")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.textPrimary)

            Text("Tell me what you want to automate and I'll build the workflow for you.")
                .font(.chatMessage)
                .foregroundStyle(.trust)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: LoveMeTheme.sm) {
                exampleChip("Every 5 minutes, generate a 3D asset in Blender")
                exampleChip("Daily at 9am, read my notes and summarize them")
                exampleChip("Every hour, check disk space and alert if low")
            }
            .padding(.top, LoveMeTheme.sm)
        }
    }

    private func exampleChip(_ text: String) -> some View {
        Button {
            promptText = text
            sendPrompt()
        } label: {
            HStack(spacing: LoveMeTheme.sm) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.electricBlue)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, LoveMeTheme.md)
            .padding(.vertical, LoveMeTheme.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Building Indicator

    private var buildingIndicator: some View {
        VStack(spacing: LoveMeTheme.md) {
            ProgressView()
                .tint(.heart)
                .scaleEffect(1.2)

            Text("Building your workflow...")
                .font(.chatMessage)
                .foregroundStyle(.trust)
        }
        .padding(.vertical, LoveMeTheme.xxl)
    }

    // MARK: - Error

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: LoveMeTheme.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.softRed)
            Text(error)
                .font(.toolDetail)
                .foregroundStyle(.textPrimary)
        }
        .padding(LoveMeTheme.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.softRed.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Result

    private func resultSection(_ result: BuilderWorkflowResult) -> some View {
        VStack(spacing: LoveMeTheme.lg) {
            WorkflowPreviewCard(
                name: result.name,
                scheduleDescription: result.scheduleDescription,
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

            if !result.description.isEmpty {
                Text(result.description)
                    .font(.toolDetail)
                    .foregroundStyle(.trust)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Action buttons
            HStack(spacing: LoveMeTheme.md) {
                Button {
                    workflowVM.builderResult = nil
                    workflowVM.builderError = nil
                    promptText = ""
                } label: {
                    Text("Try Again")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.trust)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LoveMeTheme.md)
                        .background(Color.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    workflowVM.saveBuiltWorkflow()
                    dismiss()
                } label: {
                    Text("Save Workflow")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LoveMeTheme.md)
                        .background(Color.heart)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: LoveMeTheme.sm) {
            TextField("Describe your workflow...", text: $promptText, axis: .vertical)
                .font(.chatMessage)
                .foregroundStyle(.textPrimary)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(.horizontal, LoveMeTheme.md)
                .padding(.vertical, LoveMeTheme.sm)
                .background(Color.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: LoveMeTheme.inputFieldRadius))
                .onSubmit {
                    sendPrompt()
                }

            Button {
                sendPrompt()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: LoveMeTheme.sendButtonSize))
                    .foregroundStyle(canSend ? .heart : .trust.opacity(0.3))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, LoveMeTheme.lg)
        .padding(.vertical, LoveMeTheme.sm)
        .background(.appBackground)
    }

    private var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespaces).isEmpty && !workflowVM.isBuilding
    }

    private func sendPrompt() {
        let text = promptText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        workflowVM.buildWorkflow(prompt: text)
        promptText = ""
        isInputFocused = false
    }
}
