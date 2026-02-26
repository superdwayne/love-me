import SwiftUI

struct ToolPickerSheet: View {
    let tools: [MCPToolItem]
    let isLoading: Bool
    let onSelect: (MCPToolItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filteredTools: [MCPToolItem] {
        if searchText.isEmpty { return tools }
        let query = searchText.lowercased()
        return tools.filter {
            $0.name.lowercased().contains(query) ||
            $0.description.lowercased().contains(query) ||
            $0.serverName.lowercased().contains(query)
        }
    }

    private var groupedTools: [(server: String, tools: [MCPToolItem])] {
        let grouped = Dictionary(grouping: filteredTools, by: \.serverName)
        return grouped.sorted { $0.key < $1.key }.map { (server: $0.key, tools: $0.value) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: LoveMeTheme.md) {
                        ProgressView()
                            .tint(.heart)
                        Text("Loading tools...")
                            .font(.toolDetail)
                            .foregroundStyle(.trust)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tools.isEmpty {
                    VStack(spacing: LoveMeTheme.md) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 40))
                            .foregroundStyle(.trust.opacity(0.5))
                        Text("No tools available")
                            .font(.chatMessage)
                            .foregroundStyle(.trust)
                        Text("Connect an MCP server to get started.")
                            .font(.toolDetail)
                            .foregroundStyle(.trust.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupedTools, id: \.server) { group in
                            Section {
                                ForEach(group.tools) { tool in
                                    Button {
                                        onSelect(tool)
                                    } label: {
                                        HStack(spacing: LoveMeTheme.md) {
                                            Circle()
                                                .fill(Color.electricBlue.opacity(0.15))
                                                .frame(width: 36, height: 36)
                                                .overlay {
                                                    Image(systemName: "gearshape")
                                                        .font(.system(size: 14))
                                                        .foregroundStyle(.electricBlue)
                                                }

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(tool.name)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(.textPrimary)
                                                    .lineLimit(1)

                                                if !tool.description.isEmpty {
                                                    Text(tool.description)
                                                        .font(.timestamp)
                                                        .foregroundStyle(.trust)
                                                        .lineLimit(2)
                                                }
                                            }

                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Color.surface)
                                }
                            } header: {
                                Text(group.server.uppercased())
                                    .font(.sectionHeader)
                                    .foregroundStyle(.trust)
                                    .tracking(1.2)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .searchable(text: $searchText, prompt: "Search tools")
                }
            }
            .background(.appBackground)
            .navigationTitle("Choose Tool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.trust)
                }
            }
            .toolbarBackground(.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
