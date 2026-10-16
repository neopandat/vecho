import Foundation

public struct ChatMessage: Identifiable, Codable, Equatable {
    public let id: String
    public let target: String?
    public let sessionId: String?
    public let sender: String // "user" 或 "ai"
    public var text: String
    public let time: String
    public let imageBase64: String?

    public init(id: String = UUID().uuidString, target: String? = nil, sessionId: String? = nil, sender: String, text: String, time: String = "", imageBase64: String? = nil) {
        self.id = id
        self.target = target
        self.sessionId = sessionId
        self.sender = sender
        self.text = text
        self.time = time
        self.imageBase64 = imageBase64
    }

    public var isUser: Bool {
        sender == "user"
    }

    enum CodingKeys: String, CodingKey {
        case id, target, sessionId = "session_id", sender, text, time, imageBase64
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let idStr = try? container.decode(String.self, forKey: .id), !idStr.isEmpty {
            self.id = idStr
        } else if let idInt = try? container.decode(Int.self, forKey: .id) {
            self.id = String(idInt)
        } else {
            self.id = UUID().uuidString
        }
        self.target = try? container.decodeIfPresent(String.self, forKey: .target)
        self.sessionId = try? container.decodeIfPresent(String.self, forKey: .sessionId)
        self.sender = (try? container.decode(String.self, forKey: .sender)) ?? "ai"
        self.text = (try? container.decode(String.self, forKey: .text)) ?? ""
        self.time = (try? container.decode(String.self, forKey: .time)) ?? ""
        self.imageBase64 = try? container.decodeIfPresent(String.self, forKey: .imageBase64)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(target, forKey: .target)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encode(sender, forKey: .sender)
        try container.encode(text, forKey: .text)
        try container.encode(time, forKey: .time)
        try container.encodeIfPresent(imageBase64, forKey: .imageBase64)
    }
}

/// 团队协同工作流步骤模型
public struct WorkflowStep: Identifiable, Codable {
    public var id: String
    public var name: String
    public var roleId: String
    public var status: String
    public var output: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case roleId = "role_id"
        case status
        case output
    }

    public init(id: String, name: String, roleId: String, status: String, output: String = "") {
        self.id = id
        self.name = name
        self.roleId = roleId
        self.status = status
        self.output = output
    }
}

/// 团队协同工作流实例模型
public struct WorkflowInstance: Identifiable, Codable {
    public var id: String
    public var templateId: String
    public var templateName: String
    public var topic: String
    public var status: String
    public var currentStepIndex: Int
    public var retryCount: Int
    public var steps: [WorkflowStep]

    enum CodingKeys: String, CodingKey {
        case id
        case templateId = "template_id"
        case templateName = "template_name"
        case topic
        case status
        case currentStepIndex = "current_step_index"
        case retryCount = "retry_count"
        case steps
    }
}

/// 团队协同工作流广播事件
public struct WorkflowEvent: Codable {
    public var type: String
    public var note: String?
    public var workflow: WorkflowInstance?
    public var timestamp: Int?
}

