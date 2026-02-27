import Foundation

struct Conversation: Identifiable, Codable, Sendable {
    let id: String
    var title: String
    var lastMessageAt: Date
    var messageCount: Int
    var sourceType: String?

    /// Returns a human-readable relative timestamp string
    var relativeTimestamp: String {
        let now = Date()
        let interval = now.timeIntervalSince(lastMessageAt)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 172800 {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: lastMessageAt)
        }
    }
}
