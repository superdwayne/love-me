import SwiftUI

struct InputBar: View {
    @Environment(ChatViewModel.self) private var chatVM
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var vm = chatVM

        VStack(spacing: 0) {
            // Top border
            Rectangle()
                .fill(Color.divider)
                .frame(height: 1)

            HStack(alignment: .bottom, spacing: LoveMeTheme.sm) {
                // Text input
                TextField("Message love.Me...", text: $vm.inputText, axis: .vertical)
                    .font(.chatMessage)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1...5)
                    .padding(.horizontal, LoveMeTheme.md)
                    .padding(.vertical, LoveMeTheme.sm)
                    .background(.surface)
                    .clipShape(RoundedRectangle(cornerRadius: LoveMeTheme.inputFieldRadius))
                    .focused($isFocused)
                    .accessibilityLabel("Message input")
                    .accessibilityHint("Type a message to send to love.Me")

                // Send button
                if !chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !chatVM.isStreaming {
                    Button {
                        chatVM.sendMessage()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: LoveMeTheme.sendButtonSize,
                                   height: LoveMeTheme.sendButtonSize)
                            .background(.heart)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Send message")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, LoveMeTheme.lg)
            .padding(.vertical, LoveMeTheme.sm)
        }
        .background(.inputBg)
        .animation(.easeInOut(duration: 0.15), value: chatVM.inputText.isEmpty)
    }
}
