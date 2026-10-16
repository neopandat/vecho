import Foundation

public struct SessionItem: Identifiable, Codable, Equatable {
    public let id: String
    public var title: String
    public let raw_time: String?
    public let time: String?

    public init(id: String, title: String, raw_time: String? = nil, time: String? = nil) {
        self.id = id
        self.title = title
        self.raw_time = raw_time
        self.time = time
    }

    /// 计算相对时间展示（如“刚刚”、“10分钟前”、“昨天”）
    public var displayTime: String {
        guard let raw = raw_time ?? time, !raw.isEmpty else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: raw)
        if date == nil {
            let simple = DateFormatter()
            simple.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            date = simple.date(from: raw)
        }
        guard let validDate = date else { return raw }

        let diff = Int(Date().timeIntervalSince(validDate))
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(diff / 60)分钟前" }
        if diff < 86400 { return "\(diff / 3600)小时前" }
        let days = diff / 86400
        if days == 1 { return "昨天" }
        if days < 7 { return "\(days)天前" }
        return "\(days / 7)周前"
    }
}

public struct SessionGroup: Identifiable, Codable, Equatable {
    public var id: String { group_name }
    public let group_name: String
    public var items: [SessionItem]

    public init(group_name: String, items: [SessionItem]) {
        self.group_name = group_name
        self.items = items
    }
}

public struct SessionsResponse: Codable {
    public let type_name: String
    public let can_rename: Bool
    public let groups: [SessionGroup]
}
