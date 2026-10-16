import Foundation

/// AI 编码工具用量统计数据模型 (纯一手真实数据，绝无 Mock)
public struct UsageResponse: Codable {
    public let ok: Bool
    public let data: UsageData?
    public let error: String?

    public init(ok: Bool, data: UsageData? = nil, error: String? = nil) {
        self.ok = ok
        self.data = data
        self.error = error
    }
}

public struct UsageData: Codable {
    public let generatedAt: String?
    public let source: String?
    public let tools: [String: ToolUsageData]?
    public let projects: [ProjectUsageItem]?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case source
        case tools
        case projects
    }
}

public struct ToolUsageData: Codable {
    public let available: Bool
    public let total: Int64?
    public let totalInput: Int64?
    public let totalOutput: Int64?
    public let totalCacheRead: Int64?
    public let totalCacheWrite: Int64?
    public let totalCalls: Int64?
    public let totalTurns: Int64?
    public let daily: [DailyUsageItem]?
    public let hourly: [HourlyUsageItem]?

    enum CodingKeys: String, CodingKey {
        case available
        case total
        case totalInput = "total_input"
        case totalOutput = "total_output"
        case totalCacheRead = "total_cache_read"
        case totalCacheWrite = "total_cache_write"
        case totalCalls = "total_calls"
        case totalTurns = "total_turns"
        case daily
        case hourly
    }
}

public struct DailyUsageItem: Codable, Identifiable {
    public var id: String { date }
    public let date: String
    public let total: Int64?
    public let input: Int64?
    public let output: Int64?
    public let cacheRead: Int64?
    public let cacheWrite: Int64?
    public let calls: Int64?
    public let turns: Int64?
    public let projects: [String: ProjectUsageInBucket]?
    public let hourly: [HourlyUsageItem]?

    enum CodingKeys: String, CodingKey {
        case date
        case total
        case input
        case output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case calls
        case turns
        case projects
        case hourly
    }
}

public struct HourlyUsageItem: Codable, Identifiable {
    public var id: Int { hour }
    public let hour: Int
    public let total: Int64?
    public let input: Int64?
    public let output: Int64?
    public let cacheRead: Int64?
    public let cacheWrite: Int64?
    public let calls: Int64?
    public let turns: Int64?
    public let projects: [String: ProjectUsageInBucket]?

    enum CodingKeys: String, CodingKey {
        case hour
        case total
        case input
        case output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case calls
        case turns
        case projects
    }

    public init(
        hour: Int,
        total: Int64? = nil,
        input: Int64? = nil,
        output: Int64? = nil,
        cacheRead: Int64? = nil,
        cacheWrite: Int64? = nil,
        calls: Int64? = nil,
        turns: Int64? = nil,
        projects: [String: ProjectUsageInBucket]? = nil
    ) {
        self.hour = hour
        self.total = total
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.calls = calls
        self.turns = turns
        self.projects = projects
    }
}

public struct ProjectUsageInBucket: Codable {
    public let total: Int64?
    public let calls: Int64?
    public let input: Int64?
    public let output: Int64?
    public let cacheRead: Int64?

    enum CodingKeys: String, CodingKey {
        case total
        case calls
        case input
        case output
        case cacheRead = "cache_read"
    }
}

public struct ProjectUsageItem: Codable, Identifiable {
    public var id: String { name }
    public let name: String
    public let path: String?
    public let total: Int64?
    public let input: Int64?
    public let output: Int64?
    public let cacheRead: Int64?
    public let calls: Int64?

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case total
        case input
        case output
        case cacheRead = "cache_read"
        case calls
    }
}

/// 聚合计算汇总模型
public struct AggregatedUsageSummary {
    public var total: Int64 = 0
    public var totalInput: Int64 = 0
    public var totalOutput: Int64 = 0
    public var totalCacheRead: Int64 = 0
    public var totalCacheWrite: Int64 = 0
    public var totalCalls: Int64 = 0
    public var totalTurns: Int64 = 0

    public var freshInput: Int64 {
        max(0, totalInput - totalCacheRead - totalCacheWrite)
    }

    public var cacheHitRate: Double {
        guard totalInput > 0 else { return 0.0 }
        return Double(totalCacheRead) / Double(totalInput) * 100.0
    }

    public var cacheHitRateString: String {
        guard totalInput > 0 else { return "—" }
        return String(format: "%.1f%%", cacheHitRate)
    }

    public static func formatCompactTokens(_ n: Int64) -> String {
        let val = Double(n)
        if val >= 1_000_000_000 {
            return String(format: "%.3fG", val / 1_000_000_000).replacingOccurrences(of: ".000G", with: "G")
        } else if val >= 1_000_000 {
            return String(format: "%.2fM", val / 1_000_000).replacingOccurrences(of: ".00M", with: "M")
        } else if val >= 1_000 {
            return String(format: "%.1fK", val / 1_000).replacingOccurrences(of: ".0K", with: "K")
        }
        return "\(n)"
    }

    public static func formatDelimitedNumber(_ n: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
