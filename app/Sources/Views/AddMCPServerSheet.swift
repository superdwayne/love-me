import SwiftUI

struct AddMCPServerSheet: View {
    @Bindable var settingsVM: SettingsViewModel
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var serverType = "stdio"
    @State private var command = ""
    @State private var args = ""
    @State private var url = ""
    @State private var headers = ""

    private var invalidHeaderLines: [Int] {
        let lines = headers.components(separatedBy: .newlines)
        var invalid: [Int] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.contains(":") {
                invalid.append(index + 1)
            }
        }
        return invalid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Name")
                            .foregroundStyle(.textPrimary)
                        Spacer()
                        TextField("my-server", text: $name)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .listRowBackground(Color.surface)

                    Picker("Type", selection: $serverType) {
                        Text("Stdio").tag("stdio")
                        Text("HTTP").tag("http")
                    }
                    .foregroundStyle(.textPrimary)
                    .listRowBackground(Color.surface)
                }

                if serverType == "stdio" {
                    Section {
                        HStack {
                            Text("Command")
                                .foregroundStyle(.textPrimary)
                            Spacer()
                            TextField("/usr/local/bin/node", text: $command)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.textPrimary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .listRowBackground(Color.surface)

                        VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                            Text("Arguments")
                                .foregroundStyle(.textPrimary)
                            TextField("space-separated args", text: $args)
                                .foregroundStyle(.textPrimary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(size: 14, design: .monospaced))
                        }
                        .listRowBackground(Color.surface)
                    } header: {
                        Text("STDIO CONFIGURATION")
                            .font(.sectionHeader)
                            .foregroundStyle(.trust)
                            .tracking(1.2)
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                            Text("URL")
                                .foregroundStyle(.textPrimary)
                            TextField("https://example.com/mcp", text: $url)
                                .foregroundStyle(.textPrimary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .font(.system(size: 14, design: .monospaced))
                        }
                        .listRowBackground(Color.surface)

                        VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                            Text("Headers")
                                .foregroundStyle(.textPrimary)
                            TextField("Key: Value (one per line)", text: $headers, axis: .vertical)
                                .foregroundStyle(.textPrimary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .lineLimit(3...6)
                                .font(.system(size: 14, design: .monospaced))
                            ForEach(invalidHeaderLines, id: \.self) { lineNum in
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                    Text("Line \(lineNum) is not valid (expected 'Key: Value' format)")
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(.softRed)
                            }
                        }
                        .listRowBackground(Color.surface)
                    } header: {
                        Text("HTTP CONFIGURATION")
                            .font(.sectionHeader)
                            .foregroundStyle(.trust)
                            .tracking(1.2)
                    }
                }

                if let error = settingsVM.addServerError {
                    Section {
                        HStack(spacing: SolaceTheme.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.softRed)
                                .font(.system(size: 12))
                            Text(error)
                                .font(.toolDetail)
                                .foregroundStyle(.softRed)
                        }
                        .listRowBackground(Color.surface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.appBackground)
            .navigationTitle("Add MCP Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        settingsVM.addServerError = nil
                        isPresented = false
                    }
                    .foregroundStyle(.trust)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        addServer()
                    }
                    .foregroundStyle(canAdd ? .heart : .trust.opacity(0.4))
                    .disabled(!canAdd || settingsVM.isAddingServer)
                }
            }
            .toolbarBackground(.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onChange(of: settingsVM.isAddingServer) { wasAdding, isAdding in
                // Auto-dismiss on success (was adding, stopped adding, no error)
                if wasAdding && !isAdding && settingsVM.addServerError == nil {
                    isPresented = false
                }
            }
        }
    }

    private var canAdd: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if serverType == "stdio" {
            return !command.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !url.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func addServer() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        if serverType == "stdio" {
            let trimmedCommand = command.trimmingCharacters(in: .whitespaces)
            let parsedArgs = args.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " ")
                .filter { !$0.isEmpty }

            settingsVM.addMCPServer(
                name: trimmedName,
                type: "stdio",
                command: trimmedCommand,
                args: parsedArgs.isEmpty ? nil : parsedArgs,
                url: nil,
                headers: nil
            )
        } else {
            let trimmedURL = url.trimmingCharacters(in: .whitespaces)
            var parsedHeaders: [String: String]? = nil

            let headerLines = headers.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if !headerLines.isEmpty {
                parsedHeaders = [:]
                for line in headerLines {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        let value = parts[1].trimmingCharacters(in: .whitespaces)
                        parsedHeaders?[key] = value
                    }
                }
            }

            settingsVM.addMCPServer(
                name: trimmedName,
                type: "http",
                command: nil,
                args: nil,
                url: trimmedURL,
                headers: parsedHeaders
            )
        }
    }
}
