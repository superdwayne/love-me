import SwiftUI

struct EmailDetailView: View {
    @Environment(EmailViewModel.self) private var emailVM
    let messageId: String
    @State private var showReply = false

    var body: some View {
        Group {
            if emailVM.isLoadingDetail {
                VStack(spacing: SolaceTheme.lg) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.coral)
                    Text("Loading email...")
                        .font(.chatMessage)
                        .foregroundStyle(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.appBackground)
            } else if let email = emailVM.currentEmailDetail {
                ScrollView {
                    VStack(spacing: SolaceTheme.md) {
                        headerCard(email)
                        bodyCard(email)
                        if !email.attachments.isEmpty {
                            attachmentsCard(email)
                        }
                    }
                    .padding(.horizontal, SolaceTheme.md)
                    .padding(.vertical, SolaceTheme.md)
                }
                .background(.appBackground)
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            showReply = true
                        } label: {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                        }
                        .tint(.coral)

                        Spacer()

                        Button {
                            emailVM.archiveEmail(id: email.id)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.blue)

                        Spacer()

                        Button(role: .destructive) {
                            emailVM.deleteEmail(id: email.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .sheet(isPresented: $showReply) {
                    EmailReplyView(email: email)
                }
            } else {
                VStack(spacing: SolaceTheme.md) {
                    Image(systemName: "envelope.open")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.textSecondary.opacity(0.4))
                    Text("Could not load email")
                        .font(.chatMessage)
                        .foregroundStyle(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.appBackground)
            }
        }
        .navigationTitle("Email")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            emailVM.loadEmailDetail(id: messageId)
        }
        .onDisappear {
            emailVM.currentEmailDetail = nil
            emailVM.selectedEmailId = nil
        }
    }

    // MARK: - Header Card

    private func headerCard(_ email: EmailDetail) -> some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            Text(email.subject)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.textPrimary)

            Divider()

            metadataRow(label: "From", value: email.from)

            if !email.to.isEmpty {
                metadataRow(label: "To", value: email.to.joined(separator: ", "))
            }

            if !email.cc.isEmpty {
                metadataRow(label: "Cc", value: email.cc.joined(separator: ", "))
            }

            metadataRow(label: "Date", value: formatDate(email.receivedAt))

            if !email.labels.isEmpty {
                HStack(spacing: SolaceTheme.xs) {
                    Text("Labels")
                        .font(.toolDetail)
                        .foregroundStyle(.textSecondary)
                        .frame(width: 50, alignment: .leading)

                    ForEach(email.labels, id: \.self) { label in
                        Text(label)
                            .font(.captionSmall)
                            .foregroundStyle(.white)
                            .padding(.horizontal, SolaceTheme.sm)
                            .padding(.vertical, 2)
                            .background(Color.coral.opacity(0.8))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: SolaceTheme.sm) {
            Text(label)
                .font(.toolDetail)
                .foregroundStyle(.textSecondary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.toolDetail)
                .foregroundStyle(.textPrimary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Body Card

    private func bodyCard(_ email: EmailDetail) -> some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            Text("MESSAGE")
                .font(.sectionHeaderSerif)
                .foregroundStyle(.textSecondary)
                .tracking(1.2)
                .padding(.bottom, SolaceTheme.xs)

            Text(email.bodyText)
                .font(.chatMessage)
                .foregroundStyle(.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Attachments Card

    private func attachmentsCard(_ email: EmailDetail) -> some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            Text("ATTACHMENTS")
                .font(.sectionHeaderSerif)
                .foregroundStyle(.textSecondary)
                .tracking(1.2)

            ForEach(email.attachments) { attachment in
                HStack(spacing: SolaceTheme.md) {
                    Image(systemName: iconForMimeType(attachment.mimeType))
                        .font(.system(size: 16))
                        .foregroundStyle(.coral)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.chatMessage)
                            .foregroundStyle(.textPrimary)
                            .lineLimit(1)
                        Text(formatFileSize(attachment.size))
                            .font(.captionSmall)
                            .foregroundStyle(.textSecondary)
                    }

                    Spacer()
                }
                .padding(.vertical, SolaceTheme.xs)
            }
        }
        .padding(SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func iconForMimeType(_ mimeType: String) -> String {
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType.hasPrefix("video/") { return "film" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        if mimeType.contains("pdf") { return "doc.text" }
        return "paperclip"
    }
}
