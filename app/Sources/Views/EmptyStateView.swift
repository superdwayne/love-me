import SwiftUI

struct EmptyStateView: View {
    @Environment(WebSocketClient.self) private var webSocket
    @Environment(ChatViewModel.self) private var chatVM

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good evening"
        }
    }

    private let suggestions: [(icon: String, text: String)] = [
        ("pencil.line", "Help me draft a message"),
        ("calendar", "Plan my week ahead"),
        ("lightbulb", "Brainstorm ideas with me"),
        ("envelope", "Summarize my recent emails"),
    ]

    var body: some View {
        VStack(spacing: SolaceTheme.xl) {
            Spacer()

            // Greeting
            VStack(spacing: SolaceTheme.xs) {
                Text(greeting)
                    .font(.emptyStateTitle)
                    .foregroundStyle(.textPrimary)

                Text("What can I help you with?")
                    .font(.chatMessage)
                    .foregroundStyle(.textSecondary)
            }

            // Suggestion cards
            VStack(spacing: SolaceTheme.xs) {
                ForEach(suggestions, id: \.text) { suggestion in
                    Button {
                        chatVM.inputText = suggestion.text
                        chatVM.sendMessage()
                    } label: {
                        HStack(spacing: SolaceTheme.md) {
                            Image(systemName: suggestion.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.coral)
                                .frame(width: 18)

                            Text(suggestion.text)
                                .font(.system(size: 14))
                                .foregroundStyle(.textPrimary)

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.textSecondary)
                        }
                        .padding(.horizontal, SolaceTheme.lg)
                        .padding(.vertical, SolaceTheme.md)
                        .frame(maxWidth: 300, alignment: .leading)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.cardRadius))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
            Spacer()
        }
    }
}
