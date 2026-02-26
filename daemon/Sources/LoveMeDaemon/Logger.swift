import Foundation

/// Simple logging utility with timestamps
enum Logger: Sendable {
    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return f
    }()

    private static func timestamp() -> String {
        dateFormatter.string(from: Date())
    }

    static func info(_ message: String) {
        let line = "[love.Me] [\(timestamp())] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    static func error(_ message: String) {
        FileHandle.standardError.write(
            Data("[love.Me] [\(timestamp())] ERROR: \(message)\n".utf8)
        )
    }
}
