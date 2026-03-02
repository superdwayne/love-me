import SwiftUI
import PhotosUI

struct InputBar: View {
    @Environment(ChatViewModel.self) private var chatVM
    @FocusState private var isFocused: Bool
    @State private var selectedPhotos: [PhotosPickerItem] = []

    private var canSend: Bool {
        !chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !chatVM.pendingAttachments.isEmpty
    }

    var body: some View {
        @Bindable var vm = chatVM

        VStack(spacing: 0) {
            // Top border
            Rectangle()
                .fill(Color.divider)
                .frame(height: 1)

            // Reply preview
            if let replyMsg = chatVM.replyingToMessage {
                HStack(spacing: SolaceTheme.sm) {
                    Rectangle()
                        .fill(Color.heart)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(replyMsg.role == .user ? "You" : "Solace")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.heart)
                        Text(replyMsg.content.prefix(80))
                            .font(.system(size: 13))
                            .foregroundStyle(.trust)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        chatVM.clearReply()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.trust)
                    }
                }
                .padding(.horizontal, SolaceTheme.lg)
                .padding(.vertical, SolaceTheme.sm)
                .background(.surfaceElevated)
            }

            // Attachment preview strip
            if !chatVM.pendingAttachments.isEmpty {
                attachmentPreview
            }

            HStack(alignment: .bottom, spacing: SolaceTheme.sm) {
                // Attachment button
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 5,
                    matching: .images
                ) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.trust)
                }
                .accessibilityLabel("Attach images")
                .onChange(of: selectedPhotos) { _, items in
                    Task {
                        await loadPhotos(items)
                        selectedPhotos = []
                    }
                }

                // Text input
                TextField("Message Solace...", text: $vm.inputText, axis: .vertical)
                    .font(.chatMessage)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1...5)
                    .padding(.horizontal, SolaceTheme.md)
                    .padding(.vertical, SolaceTheme.sm)
                    .background(.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.inputFieldRadius))
                    .focused($isFocused)
                    .onSubmit {
                        if canSend {
                            chatVM.sendMessage()
                        }
                    }
                    .accessibilityLabel("Message input")
                    .accessibilityHint("Type a message to send to Solace")
                    .onChange(of: chatVM.inputText) { _, newValue in
                        detectAndFetchImageURL(in: newValue)
                    }

                if chatVM.isStreaming {
                    // Stop button (while streaming/executing)
                    Button {
                        chatVM.cancelGeneration()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: SolaceTheme.sendButtonSize,
                                   height: SolaceTheme.sendButtonSize)
                            .background(.softRed)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Stop generation")
                    .transition(.scale.combined(with: .opacity))
                } else if canSend {
                    // Send button
                    Button {
                        chatVM.sendMessage()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: SolaceTheme.sendButtonSize,
                                   height: SolaceTheme.sendButtonSize)
                            .background(.heart)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Send message")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, SolaceTheme.lg)
            .padding(.vertical, SolaceTheme.sm)
        }
        .background(.inputBg)
        .animation(.easeInOut(duration: 0.15), value: canSend)
    }

    // MARK: - Attachment Preview

    private var attachmentPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SolaceTheme.sm) {
                ForEach(chatVM.pendingAttachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        if let thumbnail = attachment.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
                        } else {
                            RoundedRectangle(cornerRadius: SolaceTheme.sm)
                                .fill(Color.surfaceElevated)
                                .frame(width: 60, height: 60)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.textSecondary)
                                }
                        }

                        // Remove button
                        Button {
                            chatVM.removeAttachment(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .background(Circle().fill(.black.opacity(0.5)))
                        }
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, SolaceTheme.lg)
            .padding(.vertical, SolaceTheme.sm)
        }
    }

    // MARK: - Photo Loading

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }

            // Resize/compress to keep payloads reasonable
            let compressed = compressImage(data: data, maxDimension: 1024, quality: 0.8)
            let mimeType = "image/jpeg"
            let fileName = "photo_\(UUID().uuidString.prefix(8)).jpg"

            await MainActor.run {
                chatVM.addAttachment(data: compressed, mimeType: mimeType, fileName: fileName)
            }
        }
    }

    // MARK: - Image URL Detection

    private static let imageURLPattern = try! NSRegularExpression(
        pattern: #"https?://\S+\.(?:jpg|jpeg|png|gif|webp)(?:\?\S*)?"#,
        options: .caseInsensitive
    )

    private func detectAndFetchImageURL(in text: String) {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = Self.imageURLPattern.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else { return }

        let urlString = String(text[matchRange])
        // Remove the URL from the text field immediately
        chatVM.inputText = text.replacingCharacters(in: matchRange, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await fetchImageFromURL(urlString)
        }
    }

    private func fetchImageFromURL(_ urlString: String) async {
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            // Validate response is an image
            if let httpResponse = response as? HTTPURLResponse,
               let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
               !contentType.hasPrefix("image/") {
                return
            }

            let compressed = compressImage(data: data, maxDimension: 1024, quality: 0.8)
            let ext = (urlString as NSString).pathExtension.lowercased()
            let mimeType = ext == "png" ? "image/png" : "image/jpeg"
            let fileName = "url_\(UUID().uuidString.prefix(8)).\(ext.isEmpty ? "jpg" : ext)"

            await MainActor.run {
                chatVM.addAttachment(data: compressed, mimeType: mimeType, fileName: fileName)
            }
        } catch {
            // Silently fail — user can still type/paste normally
        }
    }

    private func compressImage(data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data {
        guard let image = UIImage(data: data) else { return data }

        let size = image.size
        let scale: CGFloat
        if size.width > maxDimension || size.height > maxDimension {
            scale = maxDimension / max(size.width, size.height)
        } else {
            scale = 1.0
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized.jpegData(compressionQuality: quality) ?? data
    }
}
