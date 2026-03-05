import SwiftUI

struct EmailReplyView: View {
    @Environment(EmailViewModel.self) private var emailVM
    @Environment(\.dismiss) private var dismiss
    let email: EmailDetail
    @State private var replyBody = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header fields
                VStack(spacing: 0) {
                    fieldRow(label: "To", value: email.from)
                    Divider().padding(.leading, 60)
                    fieldRow(label: "Subject", value: "Re: \(email.subject)")
                }
                .background(Color.surface)

                Divider()

                // Reply body
                TextEditor(text: $replyBody)
                    .font(.chatMessage)
                    .foregroundStyle(.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(SolaceTheme.md)
                    .background(.appBackground)
                    .frame(maxHeight: .infinity)

                // Original message quote
                VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                    Divider()
                    HStack(spacing: SolaceTheme.xs) {
                        Rectangle()
                            .fill(Color.dusk.opacity(0.3))
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("On \(formatDate(email.receivedAt)), \(email.from) wrote:")
                                .font(.captionSmall)
                                .foregroundStyle(.dusk)
                            Text(email.bodyText.prefix(200))
                                .font(.captionSmall)
                                .foregroundStyle(.dusk.opacity(0.7))
                                .lineLimit(4)
                        }
                    }
                    .padding(.horizontal, SolaceTheme.md)
                    .padding(.bottom, SolaceTheme.md)
                }
                .background(Color.surface)
            }
            .background(.appBackground)
            .navigationTitle("Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.dusk)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        sendReply()
                    } label: {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.coral)
                        } else {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(replyBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    .tint(.coral)
                }
            }
        }
    }

    private func fieldRow(label: String, value: String) -> some View {
        HStack(spacing: SolaceTheme.sm) {
            Text(label)
                .font(.toolDetail)
                .foregroundStyle(.dusk)
                .frame(width: 55, alignment: .trailing)
            Text(value)
                .font(.chatMessage)
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, SolaceTheme.md)
        .padding(.vertical, SolaceTheme.sm)
    }

    private func sendReply() {
        let body = replyBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSending = true
        emailVM.sendReply(messageId: email.id, threadId: email.threadId, body: body)
        // Dismiss after a short delay to allow the message to send
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
