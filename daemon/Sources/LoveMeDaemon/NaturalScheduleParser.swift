import Foundation

/// Parses natural language schedule descriptions into cron expressions
struct NaturalScheduleParser {

    struct Result: Sendable {
        let cron: String
        let description: String
    }

    /// Parse a natural language schedule string into a cron expression
    /// Returns nil if the input cannot be parsed
    static func parse(_ input: String) -> Result? {
        let text = input.lowercased().trimmingCharacters(in: .whitespaces)

        // "every N minutes" or "every N min"
        if let match = text.firstMatch(of: /every\s+(\d+)\s+min(ute)?s?/) {
            let n = Int(match.1)!
            if n > 0 && n < 60 {
                return Result(cron: "*/\(n) * * * *", description: "Every \(n) minutes")
            }
        }

        // "every minute"
        if text == "every minute" || text == "every 1 minute" {
            return Result(cron: "* * * * *", description: "Every minute")
        }

        // "every N hours" or "every N hr"
        if let match = text.firstMatch(of: /every\s+(\d+)\s+h(ou)?rs?/) {
            let n = Int(match.1)!
            if n > 0 && n <= 12 {
                return Result(cron: "0 */\(n) * * *", description: "Every \(n) hours")
            }
        }

        // "every hour" or "hourly"
        if text == "every hour" || text == "hourly" {
            return Result(cron: "0 * * * *", description: "Every hour")
        }

        // "every day at H:MM AM/PM" or "daily at H:MM AM/PM"
        if let match = text.firstMatch(of: /(every\s+day|daily)\s+at\s+(\d{1,2}):?(\d{2})?\s*(am|pm)?/) {
            var hour = Int(match.2)!
            let minute = match.3.map { Int($0)! } ?? 0
            if let period = match.4 {
                if period == "pm" && hour != 12 { hour += 12 }
                if period == "am" && hour == 12 { hour = 0 }
            }
            let desc = formatTime(hour: hour, minute: minute)
            return Result(cron: "\(minute) \(hour) * * *", description: "Every day at \(desc)")
        }

        // "every weekday at H" or "weekdays at H"
        if let match = text.firstMatch(of: /(every\s+)?weekday(s)?\s+at\s+(\d{1,2}):?(\d{2})?\s*(am|pm)?/) {
            var hour = Int(match.3)!
            let minute = match.4.map { Int($0)! } ?? 0
            if let period = match.5 {
                if period == "pm" && hour != 12 { hour += 12 }
                if period == "am" && hour == 12 { hour = 0 }
            }
            let desc = formatTime(hour: hour, minute: minute)
            return Result(cron: "\(minute) \(hour) * * 1-5", description: "Weekdays at \(desc)")
        }

        // "weekly on [day]" or "every [day]" with optional time
        let days: [(String, Int)] = [
            ("sunday", 0), ("monday", 1), ("tuesday", 2), ("wednesday", 3),
            ("thursday", 4), ("friday", 5), ("saturday", 6)
        ]
        for (dayName, dayNum) in days {
            // "every monday at 9am"
            if let match = text.firstMatch(of: try! Regex("(every|weekly\\s+on)\\s+\(dayName)(s)?\\s+at\\s+(\\d{1,2}):?(\\d{2})?\\s*(am|pm)?")) {
                guard let hourStr = match.output[3].substring,
                      var hour = Int(hourStr) else { continue }
                let minuteStr = match.output[4].substring
                let minute = minuteStr.flatMap { Int($0) } ?? 0
                let period = match.output[5].substring
                if let period = period {
                    if period == "pm" && hour != 12 { hour += 12 }
                    if period == "am" && hour == 12 { hour = 0 }
                }
                let desc = formatTime(hour: hour, minute: minute)
                return Result(cron: "\(minute) \(hour) * * \(dayNum)", description: "Every \(dayName.capitalized) at \(desc)")
            }
            // "every monday" (no time = 9am default)
            if text == "every \(dayName)" || text == "weekly on \(dayName)" {
                return Result(cron: "0 9 * * \(dayNum)", description: "Every \(dayName.capitalized) at 9:00 AM")
            }
        }

        // "every day" or "daily" (no time = midnight)
        if text == "every day" || text == "daily" {
            return Result(cron: "0 0 * * *", description: "Every day at midnight")
        }

        return nil
    }

    private static func formatTime(hour: Int, minute: Int) -> String {
        let h = hour % 24
        let period = h >= 12 ? "PM" : "AM"
        let displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        if minute == 0 {
            return "\(displayHour):00 \(period)"
        }
        return "\(displayHour):\(String(format: "%02d", minute)) \(period)"
    }
}
