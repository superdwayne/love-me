import Foundation

/// Analyzes recent conversation messages to detect workflow-worthy patterns.
/// Sends a suggestion to the client when a repeatable/automatable task is detected.
struct WorkflowSuggestionAnalyzer {

    struct Suggestion: Sendable {
        let title: String
        let description: String
        let prompt: String  // Pre-filled prompt for the workflow builder
        let confidence: Double  // 0.0–1.0
    }

    /// Analyze the last few messages in a conversation for workflow patterns.
    /// Returns a suggestion if a workflow-worthy pattern is detected, nil otherwise.
    static func analyze(messages: [StoredMessage], toolsUsed: [String]) -> Suggestion? {
        // Only analyze if we have enough context (at least a user message + assistant response)
        let recentMessages = messages.suffix(10)
        guard recentMessages.count >= 2 else { return nil }

        let userMessages = recentMessages.filter { $0.role == "user" }
        let assistantMessages = recentMessages.filter { $0.role == "assistant" }
        let toolUseMessages = recentMessages.filter { $0.role == "tool_use" }

        guard let lastUserMsg = userMessages.last else { return nil }
        let userText = lastUserMsg.content.lowercased()
        let assistantText = assistantMessages.last?.content.lowercased() ?? ""
        let combinedText = userText + " " + assistantText

        var score: Double = 0.0
        var detectedPatterns: [String] = []
        var suggestedTitle = ""
        var suggestedDescription = ""

        // ── Pattern 1: Schedule/frequency language ───────────────────
        let schedulePatterns = [
            "every day", "every morning", "every evening", "every night",
            "every hour", "every minute", "every week", "every month",
            "daily", "hourly", "weekly", "monthly",
            "at 9am", "at 8am", "at noon", "at midnight",
            "on a schedule", "scheduled", "recurring", "periodically",
            "cron", "timer", "interval",
        ]
        for pattern in schedulePatterns {
            if combinedText.contains(pattern) {
                score += 0.35
                detectedPatterns.append("schedule:\(pattern)")
                break
            }
        }

        // ── Pattern 2: Automation/workflow language ──────────────────
        let automationPatterns = [
            "automate", "automation", "workflow", "pipeline",
            "every time", "whenever", "always do", "repeat",
            "batch", "routine", "process", "chain",
            "then do", "after that", "next step", "and then",
        ]
        for pattern in automationPatterns {
            if combinedText.contains(pattern) {
                score += 0.3
                detectedPatterns.append("automation:\(pattern)")
                break
            }
        }

        // ── Pattern 3: Multiple tool calls in this turn ─────────────
        if toolUseMessages.count >= 2 {
            score += 0.25
            detectedPatterns.append("multi_tool:\(toolUseMessages.count)")
        }

        // ── Pattern 4: Cross-application discussion ─────────────────
        let appMentions = ["blender", "figma", "lens studio", "touchdesigner",
                           "github", "email", "slack", "unity", "unreal"]
        let mentionedApps = appMentions.filter { combinedText.contains($0) }
        if mentionedApps.count >= 2 {
            score += 0.2
            detectedPatterns.append("cross_app:\(mentionedApps.joined(separator: "+"))")
        }

        // ── Pattern 5: Explicit request indicators ──────────────────
        let explicitPatterns = [
            "can you do this automatically",
            "make this a workflow",
            "save this as a workflow",
            "create a workflow",
            "automate this",
            "can this be automated",
            "i want this to run",
            "set this up to run",
        ]
        for pattern in explicitPatterns {
            if userText.contains(pattern) {
                score += 0.5
                detectedPatterns.append("explicit:\(pattern)")
                break
            }
        }

        // ── Pattern 6: Tool calls with tools from different servers ─
        let uniqueServers = Set(toolsUsed)
        if uniqueServers.count >= 2 {
            score += 0.15
            detectedPatterns.append("multi_server:\(uniqueServers.joined(separator: "+"))")
        }

        // ── Threshold check ─────────────────────────────────────────
        // Need at least 0.4 confidence to suggest
        guard score >= 0.4 else { return nil }
        let confidence = min(score, 1.0)

        // ── Build suggestion text ───────────────────────────────────
        if !detectedPatterns.isEmpty {
            // Extract a meaningful title from the user's message
            let titleText = String(lastUserMsg.content.prefix(80))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            suggestedTitle = titleText.count > 60
                ? String(titleText.prefix(57)) + "..."
                : titleText

            // Build description based on detected patterns
            var descParts: [String] = []
            if detectedPatterns.contains(where: { $0.hasPrefix("schedule:") }) {
                descParts.append("runs on a schedule")
            }
            if detectedPatterns.contains(where: { $0.hasPrefix("multi_tool:") }) {
                descParts.append("uses multiple tools")
            }
            if detectedPatterns.contains(where: { $0.hasPrefix("cross_app:") }) {
                let apps = mentionedApps.map { $0.capitalized }
                descParts.append("connects \(apps.joined(separator: " & "))")
            }
            suggestedDescription = descParts.isEmpty
                ? "This looks like it could be automated as a workflow."
                : "This \(descParts.joined(separator: ", ")) — it could be a workflow."

            // Build a prompt that summarizes the conversation intent for the workflow builder
            let toolNames = toolsUsed.isEmpty ? "" : " using \(toolsUsed.joined(separator: ", "))"
            let prompt = "Based on this conversation: \(lastUserMsg.content)\(toolNames)"

            return Suggestion(
                title: suggestedTitle,
                description: suggestedDescription,
                prompt: prompt,
                confidence: confidence
            )
        }

        return nil
    }
}
