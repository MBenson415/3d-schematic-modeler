import Foundation

/// Tracks cumulative Claude API token usage across the session
@MainActor
@Observable
final class APIUsageTracker {
    static let shared = APIUsageTracker()

    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var requestCount: Int = 0

    /// Estimated cost in USD (Sonnet 4 pricing: $3/M input, $15/M output)
    var estimatedCost: Double {
        let inputCost = Double(totalInputTokens) / 1_000_000.0 * 3.0
        let outputCost = Double(totalOutputTokens) / 1_000_000.0 * 15.0
        return inputCost + outputCost
    }

    var formattedCost: String {
        String(format: "$%.4f", estimatedCost)
    }

    var formattedTokens: String {
        let total = totalInputTokens + totalOutputTokens
        if total > 1_000_000 {
            return String(format: "%.1fM tokens", Double(total) / 1_000_000.0)
        } else if total > 1_000 {
            return String(format: "%.1fK tokens", Double(total) / 1_000.0)
        }
        return "\(total) tokens"
    }

    func record(inputTokens: Int, outputTokens: Int) {
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
        requestCount += 1
    }

    func reset() {
        totalInputTokens = 0
        totalOutputTokens = 0
        requestCount = 0
    }

    private init() {}
}
