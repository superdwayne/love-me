import Foundation

// MARK: - Processed Attachment Types

/// Describes the extracted content type from a processed attachment.
enum AttachmentContentType: Sendable {
    /// Extracted text content (PDF text, plain text, CSV, JSON, ICS parsed info)
    case text(String)
    /// Path to the stored file on disk
    case filePath(String)
    /// The attachment was skipped (reason provided)
    case skipped(String)
}

/// Result of processing a single email attachment.
struct ProcessedAttachment: Sendable {
    let filename: String
    let mimeType: String
    let contentType: AttachmentContentType

    /// A human-readable summary suitable for returning to Claude.
    var summary: String {
        switch contentType {
        case .text(let content):
            return "[\(filename) (\(mimeType))]\n\(content)"
        case .filePath(let path):
            return "[\(filename) (\(mimeType))] Stored at: \(path)"
        case .skipped(let reason):
            return "[\(filename) (\(mimeType))] Skipped: \(reason)"
        }
    }
}

// MARK: - Attachment Processor

/// Processes email attachments by extracting text, storing files, and parsing structured content.
///
/// All attachments are stored under `~/.love-me/attachments/{emailId}/`.
/// Large attachments (>10 MB) are skipped with a warning.
actor AttachmentProcessor {
    private let basePath: String
    private let attachmentsDirectory: String

    /// Maximum attachment size in bytes (10 MB).
    private static let maxAttachmentSize = 10 * 1024 * 1024

    init(basePath: String) {
        self.basePath = basePath
        self.attachmentsDirectory = "\(basePath)/attachments"
    }

    /// Process an attachment and return extracted content or a file path.
    ///
    /// - Parameters:
    ///   - emailId: The Gmail message ID this attachment belongs to.
    ///   - attachmentId: The Gmail attachment ID.
    ///   - filename: Original filename of the attachment.
    ///   - mimeType: MIME type of the attachment (e.g. `application/pdf`).
    ///   - data: Raw attachment data.
    /// - Returns: A `ProcessedAttachment` with extracted content, file path, or skip reason.
    func process(
        emailId: String,
        attachmentId: String,
        filename: String,
        mimeType: String,
        data: Data
    ) async throws -> ProcessedAttachment {
        // Check size limit
        if data.count > Self.maxAttachmentSize {
            let sizeMB = String(format: "%.1f", Double(data.count) / 1_048_576.0)
            let reason = "Attachment too large (\(sizeMB) MB exceeds 10 MB limit)"
            Logger.info("AttachmentProcessor: skipping \(filename) — \(reason)")
            return ProcessedAttachment(filename: filename, mimeType: mimeType, contentType: .skipped(reason))
        }

        let normalizedMime = mimeType.lowercased().trimmingCharacters(in: .whitespaces)

        switch normalizedMime {
        case "application/pdf":
            return await processPDF(emailId: emailId, filename: filename, mimeType: mimeType, data: data)

        case "image/jpeg", "image/jpg", "image/png", "image/gif", "image/webp", "image/heic":
            return try storeAndReturnPath(emailId: emailId, filename: filename, mimeType: mimeType, data: data)

        case "text/plain", "text/csv", "text/tab-separated-values":
            return processTextContent(filename: filename, mimeType: mimeType, data: data)

        case "application/json":
            return processTextContent(filename: filename, mimeType: mimeType, data: data)

        case "text/calendar":
            return processCalendarInvite(filename: filename, mimeType: mimeType, data: data)

        default:
            // Check file extension as fallback for mislabeled MIME types
            let ext = (filename as NSString).pathExtension.lowercased()
            switch ext {
            case "pdf":
                return await processPDF(emailId: emailId, filename: filename, mimeType: mimeType, data: data)
            case "jpg", "jpeg", "png", "gif", "webp", "heic":
                return try storeAndReturnPath(emailId: emailId, filename: filename, mimeType: mimeType, data: data)
            case "txt", "csv", "tsv", "log":
                return processTextContent(filename: filename, mimeType: mimeType, data: data)
            case "json":
                return processTextContent(filename: filename, mimeType: mimeType, data: data)
            case "ics":
                return processCalendarInvite(filename: filename, mimeType: mimeType, data: data)
            default:
                // Unknown type: store the file and return metadata only
                return try storeAndReturnPath(emailId: emailId, filename: filename, mimeType: mimeType, data: data)
            }
        }
    }

    // MARK: - PDF Processing

    /// Extract text from a PDF using the system `pdftotext` utility.
    /// Falls back to storing the file if pdftotext is unavailable.
    private func processPDF(
        emailId: String,
        filename: String,
        mimeType: String,
        data: Data
    ) async -> ProcessedAttachment {
        do {
            // Write PDF to a temporary file for pdftotext
            let tempDir = NSTemporaryDirectory()
            let tempPDFPath = "\(tempDir)/loveme_\(UUID().uuidString).pdf"
            let tempTextPath = "\(tempDir)/loveme_\(UUID().uuidString).txt"

            try data.write(to: URL(fileURLWithPath: tempPDFPath))
            defer {
                try? FileManager.default.removeItem(atPath: tempPDFPath)
                try? FileManager.default.removeItem(atPath: tempTextPath)
            }

            // Run pdftotext (available on macOS via Homebrew or poppler)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pdftotext")
            process.arguments = ["-layout", tempPDFPath, tempTextPath]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                Logger.info("AttachmentProcessor: pdftotext failed with status \(process.terminationStatus) for \(filename), storing file instead")
                // Fallback: try /usr/local/bin/pdftotext or /opt/homebrew/bin/pdftotext
                if let text = try? await extractPDFWithAlternatePath(
                    pdfPath: tempPDFPath,
                    textPath: tempTextPath
                ) {
                    return ProcessedAttachment(filename: filename, mimeType: mimeType, contentType: .text(text))
                }
                return try storeAndReturnPath(emailId: emailId, filename: filename, mimeType: mimeType, data: data)
            }

            let extractedText = try String(contentsOfFile: tempTextPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if extractedText.isEmpty {
                Logger.info("AttachmentProcessor: pdftotext returned empty text for \(filename), storing file")
                return try storeAndReturnPath(emailId: emailId, filename: filename, mimeType: mimeType, data: data)
            }

            // Also store the original PDF alongside the extracted text
            let storedPath = try ensureStorageDirectory(emailId: emailId)
            let pdfStorePath = "\(storedPath)/\(sanitizeFilename(filename))"
            try data.write(to: URL(fileURLWithPath: pdfStorePath))

            Logger.info("AttachmentProcessor: extracted \(extractedText.count) chars from PDF \(filename)")
            return ProcessedAttachment(filename: filename, mimeType: mimeType, contentType: .text(extractedText))

        } catch {
            Logger.error("AttachmentProcessor: PDF processing failed for \(filename): \(error)")
            // Best effort: store the raw file
            if let result = try? storeAndReturnPath(emailId: emailId, filename: filename, mimeType: mimeType, data: data) {
                return result
            }
            return ProcessedAttachment(
                filename: filename,
                mimeType: mimeType,
                contentType: .skipped("PDF processing failed: \(error.localizedDescription)")
            )
        }
    }

    /// Try alternate pdftotext paths (Homebrew on Intel and Apple Silicon).
    private func extractPDFWithAlternatePath(pdfPath: String, textPath: String) async throws -> String? {
        let alternatePaths = ["/opt/homebrew/bin/pdftotext", "/usr/local/bin/pdftotext"]

        for path in alternatePaths {
            guard FileManager.default.fileExists(atPath: path) else { continue }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["-layout", pdfPath, textPath]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { continue }

            let text = try String(contentsOfFile: textPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                Logger.info("AttachmentProcessor: pdftotext succeeded via \(path)")
                return text
            }
        }

        return nil
    }

    // MARK: - Text/CSV/JSON Processing

    /// Return text-based content directly.
    private func processTextContent(filename: String, mimeType: String, data: Data) -> ProcessedAttachment {
        guard let text = String(data: data, encoding: .utf8) else {
            return ProcessedAttachment(
                filename: filename,
                mimeType: mimeType,
                contentType: .skipped("Unable to decode text content as UTF-8")
            )
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.info("AttachmentProcessor: extracted \(trimmed.count) chars of text from \(filename)")
        return ProcessedAttachment(filename: filename, mimeType: mimeType, contentType: .text(trimmed))
    }

    // MARK: - Calendar Invite Processing

    /// Parse basic event information from an ICS calendar invite.
    private func processCalendarInvite(filename: String, mimeType: String, data: Data) -> ProcessedAttachment {
        guard let text = String(data: data, encoding: .utf8) else {
            return ProcessedAttachment(
                filename: filename,
                mimeType: mimeType,
                contentType: .skipped("Unable to decode calendar invite as UTF-8")
            )
        }

        var summary = ""
        var dtStart = ""
        var dtEnd = ""
        var location = ""
        var description = ""
        var organizer = ""
        var attendees: [String] = []

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let value = extractICSValue(line: trimmed, key: "SUMMARY") {
                summary = value
            } else if let value = extractICSValue(line: trimmed, key: "DTSTART") {
                dtStart = formatICSDate(value)
            } else if let value = extractICSValue(line: trimmed, key: "DTEND") {
                dtEnd = formatICSDate(value)
            } else if let value = extractICSValue(line: trimmed, key: "LOCATION") {
                location = value
            } else if let value = extractICSValue(line: trimmed, key: "DESCRIPTION") {
                description = value
            } else if let value = extractICSValue(line: trimmed, key: "ORGANIZER") {
                organizer = value.replacingOccurrences(of: "mailto:", with: "")
            } else if let value = extractICSValue(line: trimmed, key: "ATTENDEE") {
                let email = value.replacingOccurrences(of: "mailto:", with: "")
                attendees.append(email)
            }
        }

        var result = "Calendar Event"
        if !summary.isEmpty { result += "\nEvent: \(summary)" }
        if !dtStart.isEmpty { result += "\nStart: \(dtStart)" }
        if !dtEnd.isEmpty { result += "\nEnd: \(dtEnd)" }
        if !location.isEmpty { result += "\nLocation: \(location)" }
        if !organizer.isEmpty { result += "\nOrganizer: \(organizer)" }
        if !attendees.isEmpty { result += "\nAttendees: \(attendees.joined(separator: ", "))" }
        if !description.isEmpty {
            // Truncate long descriptions
            let truncated = description.count > 500 ? String(description.prefix(500)) + "..." : description
            result += "\nDescription: \(truncated)"
        }

        Logger.info("AttachmentProcessor: parsed calendar invite \(filename) — \(summary)")
        return ProcessedAttachment(filename: filename, mimeType: mimeType, contentType: .text(result))
    }

    /// Extract a value for a given ICS property key.
    /// Handles both simple (`KEY:value`) and parameterized (`KEY;PARAM=val:value`) formats.
    private func extractICSValue(line: String, key: String) -> String? {
        // Exact match: "KEY:value"
        if line.hasPrefix("\(key):") {
            return String(line.dropFirst(key.count + 1))
        }
        // Parameterized: "KEY;PARAM=value:actualvalue"
        if line.hasPrefix("\(key);") {
            if let colonIndex = line.firstIndex(of: ":") {
                return String(line[line.index(after: colonIndex)...])
            }
        }
        return nil
    }

    /// Attempt to format an ICS date string into a human-readable format.
    /// ICS dates are typically `YYYYMMDDTHHmmssZ` or `YYYYMMDD`.
    private func formatICSDate(_ icsDate: String) -> String {
        let cleaned = icsDate.trimmingCharacters(in: .whitespaces)

        // Try full datetime: 20240115T140000Z
        let fullFormatter = DateFormatter()
        fullFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        fullFormatter.timeZone = TimeZone(identifier: "UTC")

        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium
        outputFormatter.timeStyle = .short
        outputFormatter.timeZone = TimeZone.current

        if let date = fullFormatter.date(from: cleaned) {
            return outputFormatter.string(from: date)
        }

        // Try datetime without Z: 20240115T140000
        fullFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
        fullFormatter.timeZone = TimeZone.current
        if let date = fullFormatter.date(from: cleaned) {
            return outputFormatter.string(from: date)
        }

        // Try date only: 20240115
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyyMMdd"
        if let date = dateOnlyFormatter.date(from: cleaned) {
            outputFormatter.timeStyle = .none
            return outputFormatter.string(from: date)
        }

        // Return the raw string if we can't parse it
        return cleaned
    }

    // MARK: - File Storage

    /// Store attachment data to disk and return the file path.
    private func storeAndReturnPath(
        emailId: String,
        filename: String,
        mimeType: String,
        data: Data
    ) throws -> ProcessedAttachment {
        let directory = try ensureStorageDirectory(emailId: emailId)
        let safeName = sanitizeFilename(filename)
        let filePath = "\(directory)/\(safeName)"

        // Avoid overwriting: append a UUID suffix if file already exists
        let finalPath: String
        if FileManager.default.fileExists(atPath: filePath) {
            let ext = (safeName as NSString).pathExtension
            let base = (safeName as NSString).deletingPathExtension
            let uniqueName = ext.isEmpty ? "\(base)_\(UUID().uuidString.prefix(8))" : "\(base)_\(UUID().uuidString.prefix(8)).\(ext)"
            finalPath = "\(directory)/\(uniqueName)"
        } else {
            finalPath = filePath
        }

        try data.write(to: URL(fileURLWithPath: finalPath))
        Logger.info("AttachmentProcessor: stored \(filename) (\(data.count) bytes) at \(finalPath)")

        return ProcessedAttachment(filename: filename, mimeType: mimeType, contentType: .filePath(finalPath))
    }

    /// Ensure the storage directory for a given email exists, creating it if necessary.
    /// Returns the full path to the email's attachment directory.
    private func ensureStorageDirectory(emailId: String) throws -> String {
        let directory = "\(attachmentsDirectory)/\(sanitizeFilename(emailId))"
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory) {
            try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Sanitize a filename by removing path-separator characters and other unsafe characters.
    private func sanitizeFilename(_ name: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let sanitized = name.components(separatedBy: unsafe).joined(separator: "_")
        // Ensure the name is not empty
        return sanitized.isEmpty ? "attachment" : sanitized
    }
}
