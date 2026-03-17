import SwiftUI

struct ChatSearchBar: View {
    @Environment(ChatViewModel.self) private var chatVM
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var vm = chatVM

        HStack(spacing: SolaceTheme.sm) {
            // Search field
            HStack(spacing: SolaceTheme.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.textSecondary)

                TextField("Search messages...", text: $vm.searchQuery)
                    .font(.system(size: 14))
                    .foregroundStyle(.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                    .onChange(of: chatVM.searchQuery) { _, _ in
                        chatVM.updateSearchResults()
                    }

                if !chatVM.searchQuery.isEmpty {
                    Button {
                        chatVM.searchQuery = ""
                        chatVM.updateSearchResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.textSecondary)
                    }
                }
            }
            .padding(.horizontal, SolaceTheme.sm)
            .padding(.vertical, SolaceTheme.sm)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))

            // Match counter and navigation
            if !chatVM.searchMatches.isEmpty {
                Text("\(chatVM.currentMatchIndex + 1) of \(chatVM.searchMatches.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.textSecondary)
                    .monospacedDigit()
                    .frame(minWidth: 50)

                HStack(spacing: 2) {
                    Button {
                        chatVM.previousMatch()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Color.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Button {
                        chatVM.nextMatch()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Color.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            } else if !chatVM.searchQuery.isEmpty {
                Text("No results")
                    .font(.system(size: 12))
                    .foregroundStyle(.textSecondary.opacity(0.6))
            }

            // Done button
            Button {
                chatVM.toggleSearch()
            } label: {
                Text("Done")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.electricBlue)
            }
        }
        .padding(.horizontal, SolaceTheme.lg)
        .padding(.vertical, SolaceTheme.sm)
        .background(.surface)
        .onAppear {
            isFocused = true
        }
    }
}
