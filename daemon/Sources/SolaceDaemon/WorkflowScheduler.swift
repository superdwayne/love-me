import Foundation

// MARK: - WorkflowScheduler

/// Manages cron-based scheduling for workflows. Parses standard 5-field cron
/// expressions and uses Swift concurrency to sleep until the next fire time.
actor WorkflowScheduler {

    // MARK: - Properties

    /// Active schedule loops keyed by workflow ID.
    private var scheduledTasks: [String: Task<Void, Never>] = [:]

    /// Callback invoked on the actor's executor whenever a cron fires.
    private let onFire: @Sendable (WorkflowDefinition) async -> Void

    // MARK: - Init

    init(onFire: @escaping @Sendable (WorkflowDefinition) async -> Void) {
        self.onFire = onFire
    }

    // MARK: - Public API

    /// Schedule all enabled cron workflows, replacing any existing schedules.
    func scheduleAll(_ workflows: [WorkflowDefinition]) {
        removeAll()
        for workflow in workflows where workflow.enabled {
            add(workflow: workflow)
        }
    }

    /// Schedule a single workflow if it has a cron trigger.
    func add(workflow: WorkflowDefinition) {
        guard case .cron(let expression) = workflow.trigger else { return }

        // Cancel an existing schedule for this workflow before replacing it.
        scheduledTasks[workflow.id]?.cancel()

        Logger.info("Scheduling workflow '\(workflow.name)' with cron '\(expression)' (\(Self.describeSchedule(expression)))")
        scheduledTasks[workflow.id] = scheduleLoop(workflow: workflow, expression: expression)
    }

    /// Remove a scheduled workflow by its ID.
    func remove(workflowId: String) {
        scheduledTasks[workflowId]?.cancel()
        scheduledTasks.removeValue(forKey: workflowId)
    }

    /// Remove all scheduled workflows.
    func removeAll() {
        for task in scheduledTasks.values {
            task.cancel()
        }
        scheduledTasks.removeAll()
    }

    // MARK: - Schedule Loop

    private func scheduleLoop(workflow: WorkflowDefinition, expression: String) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let nextDate = Self.nextFireDate(cron: expression) else {
                    Logger.error("Invalid cron expression for workflow '\(workflow.name)': \(expression)")
                    return
                }

                let delay = nextDate.timeIntervalSinceNow
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                guard !Task.isCancelled else { return }

                Logger.info("Cron fired for workflow '\(workflow.name)'")
                await self?.onFire(workflow)
            }
        }
    }

    // MARK: - Cron Parser

    /// Returns the next `Date` that matches the given 5-field cron expression,
    /// searching forward minute-by-minute from `after` up to 366 days.
    ///
    /// Cron fields: minute hour day-of-month month day-of-week
    ///
    /// Supported syntax per field:
    ///   - `*`       — any value
    ///   - `5`       — specific value
    ///   - `1-5`     — inclusive range
    ///   - `1,3,5`   — list
    ///   - `*/5`     — step (every N from start of range)
    ///   - `1-10/2`  — range with step
    static func nextFireDate(cron expression: String, after: Date = Date()) -> Date? {
        let fields = expression.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        guard fields.count == 5 else { return nil }

        let fieldRanges: [ClosedRange<Int>] = [
            0...59,  // minute
            0...23,  // hour
            1...31,  // day of month
            1...12,  // month
            0...6    // day of week (0 = Sunday)
        ]

        // Parse each field into a Set of allowed integer values.
        var allowedValues: [Set<Int>] = []
        for (i, field) in fields.enumerated() {
            guard let values = parseField(field, range: fieldRanges[i]) else {
                return nil
            }
            allowedValues.append(values)
        }

        let calendar = Calendar.current

        // Start searching from the next whole minute after `after`.
        guard var candidate = calendar.date(bySetting: .second, value: 0, of: after) else {
            return nil
        }
        // Advance by one minute so we never return the current minute.
        guard let startCandidate = calendar.date(byAdding: .minute, value: 1, to: candidate) else {
            return nil
        }
        candidate = startCandidate

        let maxDate = calendar.date(byAdding: .day, value: 366, to: after)!

        while candidate <= maxDate {
            let comps = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: candidate)

            guard let minute = comps.minute,
                  let hour = comps.hour,
                  let day = comps.day,
                  let month = comps.month,
                  let weekday = comps.weekday else {
                return nil
            }

            // Calendar.weekday: 1=Sunday..7=Saturday -> cron: 0=Sunday..6=Saturday
            let cronWeekday = weekday - 1

            if allowedValues[0].contains(minute)
                && allowedValues[1].contains(hour)
                && allowedValues[2].contains(day)
                && allowedValues[3].contains(month)
                && allowedValues[4].contains(cronWeekday)
            {
                return candidate
            }

            guard let next = calendar.date(byAdding: .minute, value: 1, to: candidate) else {
                return nil
            }
            candidate = next
        }

        return nil
    }

    // MARK: - Field Parser

    /// Parse a single cron field (e.g. `*/5`, `1-3`, `1,4,7`) into a set of
    /// allowed integer values within the given range.
    private static func parseField(_ field: String, range: ClosedRange<Int>) -> Set<Int>? {
        var result = Set<Int>()

        // A field may be a comma-separated list of atoms.
        let atoms = field.split(separator: ",").map(String.init)
        for atom in atoms {
            guard let values = parseAtom(atom, range: range) else { return nil }
            result.formUnion(values)
        }

        return result.isEmpty ? nil : result
    }

    /// Parse a single atom which may be `*`, a number, a range, or any of
    /// those combined with a `/step` suffix.
    private static func parseAtom(_ atom: String, range: ClosedRange<Int>) -> Set<Int>? {
        var base = atom
        var step: Int? = nil

        // Check for step suffix.
        if let slashIndex = atom.firstIndex(of: "/") {
            let stepStr = String(atom[atom.index(after: slashIndex)...])
            guard let s = Int(stepStr), s > 0 else { return nil }
            step = s
            base = String(atom[..<slashIndex])
        }

        var values: [Int]

        if base == "*" {
            values = Array(range)
        } else if let dashIndex = base.firstIndex(of: "-") {
            // Range: e.g. "1-5"
            guard let low = Int(String(base[..<dashIndex])),
                  let high = Int(String(base[base.index(after: dashIndex)...])),
                  low >= range.lowerBound,
                  high <= range.upperBound,
                  low <= high else {
                return nil
            }
            values = Array(low...high)
        } else {
            // Single value.
            guard let val = Int(base),
                  range.contains(val) else {
                return nil
            }
            values = [val]
        }

        // Apply step if present.
        if let step = step {
            var stepped: [Int] = []
            for (index, value) in values.enumerated() {
                if index % step == 0 {
                    stepped.append(value)
                }
            }
            values = stepped
        }

        return Set(values)
    }

    // MARK: - Describe Schedule

    /// Returns a human-readable description for common cron patterns.
    static func describeSchedule(_ expression: String) -> String {
        let fields = expression.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        guard fields.count == 5 else { return expression }

        let minute = fields[0]
        let hour = fields[1]
        let dayOfMonth = fields[2]
        let month = fields[3]
        let dayOfWeek = fields[4]

        // Every minute: * * * * *
        if minute == "*" && hour == "*" && dayOfMonth == "*" && month == "*" && dayOfWeek == "*" {
            return "Every minute"
        }

        // Every N minutes: */N * * * *
        if minute.hasPrefix("*/"), hour == "*", dayOfMonth == "*", month == "*", dayOfWeek == "*",
           let n = Int(String(minute.dropFirst(2))) {
            return "Every \(n) minute\(n == 1 ? "" : "s")"
        }

        // Every N hours: 0 */N * * *
        if minute == "0", hour.hasPrefix("*/"), dayOfMonth == "*", month == "*", dayOfWeek == "*",
           let n = Int(String(hour.dropFirst(2))) {
            return "Every \(n) hour\(n == 1 ? "" : "s")"
        }

        // Specific minute every hour: M * * * *
        if let m = Int(minute), hour == "*", dayOfMonth == "*", month == "*", dayOfWeek == "*" {
            return "Every hour at minute \(m)"
        }

        // Daily at specific time: M H * * *
        if let m = Int(minute), let h = Int(hour), dayOfMonth == "*", month == "*", dayOfWeek == "*" {
            return "Daily at \(formatTime(hour: h, minute: m))"
        }

        // Weekly on specific day: M H * * D
        if let m = Int(minute), let h = Int(hour), dayOfMonth == "*", month == "*",
           let d = Int(dayOfWeek) {
            let dayName = dayOfWeekName(d)
            return "Every \(dayName) at \(formatTime(hour: h, minute: m))"
        }

        // Monthly on specific day: M H D * *
        if let m = Int(minute), let h = Int(hour), let dom = Int(dayOfMonth), month == "*", dayOfWeek == "*" {
            return "Monthly on day \(dom) at \(formatTime(hour: h, minute: m))"
        }

        // Yearly on specific date: M H D Mo *
        if let m = Int(minute), let h = Int(hour), let dom = Int(dayOfMonth),
           let mo = Int(month), dayOfWeek == "*" {
            let monthName = monthName(mo)
            return "\(monthName) \(dom) at \(formatTime(hour: h, minute: m))"
        }

        // Fallback: just return the raw expression.
        return expression
    }

    // MARK: - Formatting Helpers

    private static func formatTime(hour: Int, minute: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }

    private static func dayOfWeekName(_ day: Int) -> String {
        switch day {
        case 0: return "Sunday"
        case 1: return "Monday"
        case 2: return "Tuesday"
        case 3: return "Wednesday"
        case 4: return "Thursday"
        case 5: return "Friday"
        case 6: return "Saturday"
        default: return "Day \(day)"
        }
    }

    private static func monthName(_ month: Int) -> String {
        switch month {
        case 1:  return "January"
        case 2:  return "February"
        case 3:  return "March"
        case 4:  return "April"
        case 5:  return "May"
        case 6:  return "June"
        case 7:  return "July"
        case 8:  return "August"
        case 9:  return "September"
        case 10: return "October"
        case 11: return "November"
        case 12: return "December"
        default: return "Month \(month)"
        }
    }
}
