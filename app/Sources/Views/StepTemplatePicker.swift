import SwiftUI

struct StepTemplatePicker: View {
    let templates: [StepTemplate]
    let onSelect: (StepTemplate) -> Void
    let onScratch: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: StepTemplateCategory?

    private var filteredTemplates: [StepTemplate] {
        var result = templates
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
        NavigationStack {
            VStack(spacing: 0) {
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

                Divider().background(.divider)

                // Template list
                List {
                    // Start from scratch option
                    Button {
                        onScratch()
                        dismiss()
                    } label: {
                        HStack(spacing: SolaceTheme.md) {
                            Circle()
                                .fill(Color.textSecondary.opacity(0.2))
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.textSecondary)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start from scratch")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.textPrimary)
                                Text("Choose a tool manually")
                                    .font(.timestamp)
                                    .foregroundStyle(.textSecondary)
                            }

                            Spacer()
                        }
                    }
                    .listRowBackground(Color.surface)

                    // Templates
                    ForEach(filteredTemplates) { template in
                        Button {
                            onSelect(template)
                            dismiss()
                        } label: {
                            HStack(spacing: SolaceTheme.md) {
                                Circle()
                                    .fill(template.iconColor.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        Image(systemName: template.icon)
                                            .font(.system(size: 14))
                                            .foregroundStyle(template.iconColor)
                                    }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.textPrimary)
                                        .lineLimit(1)

                                    Text(template.description)
                                        .font(.timestamp)
                                        .foregroundStyle(.textSecondary)
                                        .lineLimit(2)

                                    if !template.serverName.isEmpty {
                                        Text(template.serverName)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.electricBlue)
                                    }
                                }

                                Spacer()
                            }
                        }
                        .listRowBackground(Color.surface)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .background(.appBackground)
            .navigationTitle("Add Step")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search templates...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.textSecondary)
                }
            }
            .toolbarBackground(.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

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
            .foregroundStyle(isSelected ? .white : .textSecondary)
            .padding(.horizontal, SolaceTheme.md)
            .padding(.vertical, SolaceTheme.sm)
            .background(isSelected ? Color.heart : Color.surfaceElevated)
            .clipShape(Capsule())
        }
    }
}
