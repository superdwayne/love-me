import SwiftUI

struct StepInputEditor: View {
    @Binding var step: EditableStep
    let schema: [SchemaProperty]

    var body: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            ForEach(schema, id: \.name) { prop in
                inputField(for: prop)
            }
        }
        .padding(.vertical, SolaceTheme.xs)
    }

    @ViewBuilder
    private func inputField(for prop: SchemaProperty) -> some View {
        VStack(alignment: .leading, spacing: SolaceTheme.xs) {
            // Label with required indicator
            HStack(spacing: SolaceTheme.xs) {
                Text(prop.name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.electricBlue)
                if prop.isRequired {
                    Text("*")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.softRed)
                }
            }

            // Description hint
            if !prop.description.isEmpty {
                Text(prop.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.textSecondary)
                    .lineLimit(2)
            }

            // Input control based on type
            switch prop.type {
            case "boolean":
                Toggle(isOn: boolBinding(for: prop.name)) {
                    EmptyView()
                }
                .tint(.coral)
                .labelsHidden()

            case _ where prop.enumValues != nil && !(prop.enumValues!.isEmpty):
                Picker("", selection: stringBinding(for: prop.name)) {
                    Text("Select...").tag("")
                    ForEach(prop.enumValues!, id: \.self) { val in
                        Text(val).tag(val)
                    }
                }
                .pickerStyle(.menu)
                .tint(.electricBlue)

            default:
                // String, number, integer, array, object -> text field
                TextField(
                    prop.description.isEmpty ? prop.name : prop.description,
                    text: stringBinding(for: prop.name),
                    axis: prop.type == "string" ? .vertical : .horizontal
                )
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.textPrimary)
                .lineLimit(prop.type == "string" ? 1...4 : 1...1)
                .padding(SolaceTheme.sm)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.xs))
            }

            // Validation warning for missing required fields
            if prop.isRequired && (step.inputs[prop.name]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) {
                HStack(spacing: SolaceTheme.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.amberGlow)
                    Text("Required")
                        .font(.system(size: 10))
                        .foregroundStyle(.amberGlow)
                }
            }
        }
    }

    // MARK: - Bindings

    private func stringBinding(for key: String) -> Binding<String> {
        Binding(
            get: { step.inputs[key] ?? "" },
            set: { step.inputs[key] = $0 }
        )
    }

    private func boolBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: {
                let val = step.inputs[key] ?? "false"
                return val == "true" || val == "1"
            },
            set: { step.inputs[key] = $0 ? "true" : "false" }
        )
    }
}
