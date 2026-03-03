import SwiftUI
import PhotosUI
import AVFoundation

struct InputBar: View {
    @Environment(ChatViewModel.self) private var chatVM
    @FocusState private var isFocused: Bool
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var audioRecorder = AudioRecorderManager()

    private var canSend: Bool {
        let hasText = !chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !chatVM.pendingAttachments.isEmpty
        let stillCompressing = chatVM.hasLoadingAttachments
        return (hasText || hasAttachments) && !stillCompressing
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

            if audioRecorder.isRecording {
                // Recording indicator bar
                HStack(spacing: SolaceTheme.sm) {
                    // Cancel recording
                    Button {
                        audioRecorder.cancelRecording()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.trust)
                    }
                    .accessibilityLabel("Cancel recording")

                    // Recording indicator
                    HStack(spacing: SolaceTheme.sm) {
                        Circle()
                            .fill(Color.softRed)
                            .frame(width: 10, height: 10)

                        Text("Recording")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.textPrimary)

                        Text(audioRecorder.formattedDuration)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.trust)

                        Spacer()
                    }
                    .padding(.horizontal, SolaceTheme.md)
                    .padding(.vertical, SolaceTheme.md)
                    .background(.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.inputFieldRadius))

                    // Stop and send
                    Button {
                        stopRecordingAndAttach()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.softRed)
                    }
                    .accessibilityLabel("Stop recording")
                }
                .padding(.horizontal, SolaceTheme.lg)
                .padding(.vertical, SolaceTheme.sm)
                .transition(.opacity)
            } else {
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
                    ChatTextInput(
                        text: $vm.inputText,
                        onReturn: {
                            if canSend {
                                chatVM.sendMessage()
                            }
                        }
                    )
                    .frame(minHeight: 36, maxHeight: 120)
                    .padding(.horizontal, SolaceTheme.md)
                    .padding(.vertical, SolaceTheme.sm)
                    .background(.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.inputFieldRadius))
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
                    } else {
                        // Mic button (shown when text is empty and no pending attachments)
                        Button {
                            requestMicAndRecord()
                        } label: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: SolaceTheme.sendButtonSize,
                                       height: SolaceTheme.sendButtonSize)
                                .background(.trust)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Record voice note")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, SolaceTheme.lg)
                .padding(.vertical, SolaceTheme.sm)
            }
        }
        .background(.inputBg)
        .animation(.easeInOut(duration: 0.15), value: canSend)
        .animation(.easeInOut(duration: 0.2), value: audioRecorder.isRecording)
    }

    // MARK: - Attachment Preview

    private var attachmentPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SolaceTheme.sm) {
                ForEach(chatVM.pendingAttachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        if attachment.isLoading {
                            RoundedRectangle(cornerRadius: SolaceTheme.sm)
                                .fill(Color.surfaceElevated)
                                .frame(width: 60, height: 60)
                                .overlay {
                                    ProgressView()
                                        .tint(.textSecondary)
                                }
                        } else if attachment.isAudio {
                            // Audio attachment preview
                            VStack(spacing: SolaceTheme.xs) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.heart)
                                if let dur = attachment.audioDuration {
                                    Text(formatDuration(dur))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.trust)
                                }
                            }
                            .frame(width: 60, height: 60)
                            .background(Color.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
                        } else if let thumbnail = attachment.thumbnail {
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

    // MARK: - Voice Recording

    private func requestMicAndRecord() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            audioRecorder.startRecording()
        case .denied:
            // Could show an alert directing user to Settings
            break
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                if granted {
                    Task { @MainActor in
                        audioRecorder.startRecording()
                    }
                }
            }
        @unknown default:
            break
        }
    }

    private func stopRecordingAndAttach() {
        guard let result = audioRecorder.stopRecording() else { return }
        chatVM.addVoiceNote(data: result.data, duration: result.duration)
        // Auto-send the voice note immediately
        chatVM.sendMessage()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    // MARK: - Photo Loading

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }

            let placeholderId = UUID().uuidString
            let fileName = "photo_\(placeholderId.prefix(8)).jpg"
            let mimeType = "image/jpeg"

            // Add loading placeholder immediately so the user sees it
            await MainActor.run {
                chatVM.addLoadingPlaceholder(id: placeholderId, fileName: fileName)
            }

            // Compress in background with concurrency limit
            let compressed = await compressImage(data: data, maxDimension: 1024, quality: 0.8)

            await MainActor.run {
                chatVM.finalizeAttachment(id: placeholderId, data: compressed, mimeType: mimeType, fileName: fileName)
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

        let placeholderId = UUID().uuidString
        let ext = (urlString as NSString).pathExtension.lowercased()
        let fileName = "url_\(placeholderId.prefix(8)).\(ext.isEmpty ? "jpg" : ext)"
        let mimeType = ext == "png" ? "image/png" : "image/jpeg"

        // Add loading placeholder immediately
        await MainActor.run {
            chatVM.addLoadingPlaceholder(id: placeholderId, fileName: fileName)
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            // Validate response is an image
            if let httpResponse = response as? HTTPURLResponse,
               let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
               !contentType.hasPrefix("image/") {
                // Not an image — remove the placeholder
                await MainActor.run {
                    chatVM.pendingAttachments.removeAll { $0.id == placeholderId }
                }
                return
            }

            let compressed = await compressImage(data: data, maxDimension: 1024, quality: 0.8)

            await MainActor.run {
                chatVM.finalizeAttachment(id: placeholderId, data: compressed, mimeType: mimeType, fileName: fileName)
            }
        } catch {
            // Remove the placeholder on failure
            await MainActor.run {
                chatVM.pendingAttachments.removeAll { $0.id == placeholderId }
            }
        }
    }

    private func compressImage(data: Data, maxDimension: CGFloat, quality: CGFloat) async -> Data {
        await Self.compressionLimiter.waitForSlot()
        defer { Task { await Self.compressionLimiter.releaseSlot() } }

        // Run the CPU-intensive rendering work off the main thread
        let result = await Task.detached(priority: .userInitiated) {
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
        }.value

        return result
    }

    // MARK: - Concurrency Limiter

    private static let compressionLimiter = CompressionLimiter()
}

// MARK: - UITextView Wrapper (reliable paste support)

/// Custom UITextView subclass that guarantees paste works on iOS 16+.
/// iOS 16 introduced paste-permission prompts that can silently swallow paste
/// actions on a plain UITextView. By explicitly overriding `paste(_:)` and
/// `canPerformAction(_:withSender:)` we ensure the pasteboard is always read.
class PastableTextView: UITextView {
    /// Called back after a successful paste so the coordinator can sync state.
    var onPaste: (() -> Void)?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        // Read the pasteboard ourselves so we never silently discard content.
        let pb = UIPasteboard.general
        if let string = pb.string {
            // Insert at the current selection, replacing any selected range.
            let loc = selectedRange.location
            let len = selectedRange.length
            if let current = text,
               let start = current.index(current.startIndex, offsetBy: loc, limitedBy: current.endIndex),
               let end   = current.index(start, offsetBy: len, limitedBy: current.endIndex) {
                let updated = current.replacingCharacters(in: start..<end, with: string)
                text = updated
                // Move cursor to end of pasted text
                let newCursorPos = loc + string.utf16.count
                selectedRange = NSRange(location: newCursorPos, length: 0)
            } else {
                // Fallback: append
                text = (text ?? "") + string
                let newLen = (text ?? "").utf16.count
                selectedRange = NSRange(location: newLen, length: 0)
            }
            onPaste?()
        } else {
            // Non-string pasteboard content (images, etc.) — fall back to default
            super.paste(sender)
            onPaste?()
        }
    }
}

struct ChatTextInput: UIViewRepresentable {
    @Binding var text: String
    var onReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PastableTextView {
        let tv = PastableTextView()
        tv.delegate = context.coordinator
        tv.onPaste = { [weak tv] in
            guard let tv else { return }
            context.coordinator.syncText(from: tv)
        }
        tv.font = UIFont.systemFont(ofSize: 16)
        tv.textColor = UIColor.label
        tv.backgroundColor = .clear
        tv.isScrollEnabled = true
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.returnKeyType = .send
        tv.allowsEditingTextAttributes = false
        tv.autocorrectionType = .default
        tv.spellCheckingType = .default

        // Placeholder
        let placeholder = UILabel()
        placeholder.text = "Message Solace..."
        placeholder.font = tv.font
        placeholder.textColor = UIColor.secondaryLabel.withAlphaComponent(0.5)
        placeholder.tag = 999
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: tv.leadingAnchor),
            placeholder.topAnchor.constraint(equalTo: tv.topAnchor),
        ])

        return tv
    }

    func updateUIView(_ tv: PastableTextView, context: Context) {
        // Guard against overwriting the UITextView while the user is actively
        // typing or pasting. Only push SwiftUI state into UIKit when the two
        // have genuinely diverged AND the user is not mid-edit.
        if tv.text != text && !context.coordinator.isEditing {
            tv.text = text
        }
        // Show/hide placeholder
        if let placeholder = tv.viewWithTag(999) as? UILabel {
            placeholder.isHidden = !(tv.text ?? "").isEmpty
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        let parent: ChatTextInput
        /// True while the UITextView is the first responder and actively being
        /// edited. Prevents `updateUIView` from clobbering in-flight changes.
        var isEditing = false

        init(parent: ChatTextInput) {
            self.parent = parent
        }

        /// Shared helper to push UITextView text into the SwiftUI binding.
        func syncText(from textView: UITextView) {
            let newText = textView.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
            // Show/hide placeholder
            if let placeholder = textView.viewWithTag(999) as? UILabel {
                placeholder.isHidden = !newText.isEmpty
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            // Final sync when keyboard dismisses
            syncText(from: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            syncText(from: textView)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementString text: String) -> Bool {
            // Only intercept the Return key (single "\n" character typed via keyboard).
            // Multi-character strings (including pasted text that may contain newlines)
            // must always be allowed through.
            if text == "\n" && text.count == 1 {
                parent.onReturn()
                return false
            }
            return true
        }
    }
}

/// Actor that limits concurrent compression operations to avoid memory spikes.
private actor CompressionLimiter {
    private let limit = 3
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitForSlot() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func releaseSlot() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            active -= 1
        }
    }
}
