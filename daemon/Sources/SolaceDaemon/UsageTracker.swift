import Foundation

/// Summary of API token usage for a session
struct UsageSummary: Sendable {
    let totalInput: Int
    let totalOutput: Int
    let totalCacheCreation: Int
    let totalCacheRead: Int
    let requestCount: Int
    let cacheRatio: Double
}

/// Tracks API token usage per session for cost visibility
actor UsageTracker {
    private var totalInput = 0
    private var totalOutput = 0
    private var totalCacheCreation = 0
    private var totalCacheRead = 0
    private var requestCount = 0

    func recordUsage(input: Int, output: Int, cacheCreation: Int, cacheRead: Int) {
        totalInput += input
        totalOutput += output
        totalCacheCreation += cacheCreation
        totalCacheRead += cacheRead
        requestCount += 1

        Logger.info("[Usage] Request #\(requestCount): in=\(input) out=\(output) cache_create=\(cacheCreation) cache_read=\(cacheRead)")

        if requestCount % 10 == 0 {
            logSummary()
        }
    }

    func getSummary() -> UsageSummary {
        UsageSummary(
            totalInput: totalInput,
            totalOutput: totalOutput,
            totalCacheCreation: totalCacheCreation,
            totalCacheRead: totalCacheRead,
            requestCount: requestCount,
            cacheRatio: computeCacheRatio()
        )
    }

    func reset() {
        totalInput = 0
        totalOutput = 0
        totalCacheCreation = 0
        totalCacheRead = 0
        requestCount = 0
    }

    func logSummary() {
        let ratio = computeCacheRatio()
        Logger.info("[Usage Summary] \(requestCount) requests — total_in=\(totalInput) total_out=\(totalOutput) cache_created=\(totalCacheCreation) cache_read=\(totalCacheRead) cache_ratio=\(String(format: "%.1f", ratio))%")
    }

    private func computeCacheRatio() -> Double {
        let totalInputTokens = totalCacheRead + totalCacheCreation + totalInput
        guard totalInputTokens > 0 else { return 0 }
        return Double(totalCacheRead) / Double(totalInputTokens) * 100
    }
}
