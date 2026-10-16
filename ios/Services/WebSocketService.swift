import Foundation
import Combine

/// 原生 WebSocket 双向全双工长连接管理器（主线程隔离与安全重连）
@MainActor
public class WebSocketService: ObservableObject {
    public static let shared = WebSocketService()

    @Published public var isConnected: Bool = false
    @Published public var receivedMessage: ChatMessage?
    @Published public var deletedMessageId: String?
    @Published public var latestWorkflowEvent: WorkflowEvent?

    private var currentHost: String = "192.168.31.188"
    private var currentPort: Int = 31188
    private var isManuallyDisconnected: Bool = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var pingTimer: Timer?
    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var serverURL: URL = URL(string: "ws://192.168.31.188:31188/ws")!

    private init() {}

    public func connect(host: String? = nil, port: Int? = nil) {
        if let h = host, !h.trimmingCharacters(in: .whitespaces).isEmpty {
            self.currentHost = h.trimmingCharacters(in: .whitespaces)
        }
        if let p = port, p > 0 {
            self.currentPort = p
        }

        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        isManuallyDisconnected = false

        stopPingTimer()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        let trimmed = currentHost
        var urlString: String
        if trimmed.hasPrefix("wss://") || trimmed.hasPrefix("ws://") {
            urlString = trimmed.hasSuffix("/ws") ? trimmed : "\(trimmed)/ws"
        } else if trimmed.hasPrefix("https://") {
            let replaced = trimmed.replacingOccurrences(of: "https://", with: "wss://")
            urlString = replaced.hasSuffix("/ws") ? replaced : "\(replaced)/ws"
        } else if trimmed.hasPrefix("http://") {
            let replaced = trimmed.replacingOccurrences(of: "http://", with: "ws://")
            urlString = replaced.hasSuffix("/ws") ? replaced : "\(replaced)/ws"
        } else if trimmed.contains(".") && !trimmed.contains(":") && !trimmed.allSatisfy({ $0.isNumber || $0 == "." }) {
            urlString = "wss://\(trimmed)/ws"
        } else {
            urlString = "ws://\(trimmed):\(currentPort)/ws"
        }

        guard let url = URL(string: urlString) else {
            return
        }
        self.serverURL = url

        if session == nil {
            session = URLSession(configuration: .default)
        }

        let task = session!.webSocketTask(with: serverURL)
        self.webSocketTask = task
        task.resume()

        listenForMessages(for: task)
        startPingTimer()
    }

    public func disconnect() {
        isManuallyDisconnected = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        stopPingTimer()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        self.isConnected = false
    }

    private func listenForMessages(for task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            DispatchQueue.main.async {
                guard let self = self, let current = self.webSocketTask, current === task else {
                    return
                }
                switch result {
                case .failure:
                    self.isConnected = false
                    self.scheduleReconnect()
                case .success(let message):
                    self.isConnected = true
                    switch message {
                    case .string(let text):
                        self.handleIncomingText(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleIncomingText(text)
                        }
                    @unknown default:
                        break
                    }
                    if let activeTask = self.webSocketTask, activeTask === task {
                        self.listenForMessages(for: activeTask)
                    }
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard !isManuallyDisconnected else { return }
        reconnectWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isManuallyDisconnected else { return }
            self.connect()
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
    }

    private func handleIncomingText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let type = json["type"] as? String ?? ""
        if type == "message" {
            let sender = json["sender"] as? String ?? "ai"
            let msgText = json["text"] as? String ?? ""
            let timeStr = json["time"] as? String ?? ""
            let idStr = json["id"] != nil ? String(describing: json["id"]!) : UUID().uuidString
            let targetStr = json["target"] as? String
            let sessionIdStr = json["session_id"] as? String
            let newMsg = ChatMessage(id: idStr, target: targetStr, sessionId: sessionIdStr, sender: sender, text: msgText, time: timeStr)
            self.receivedMessage = newMsg
        } else if type == "connected" {
            self.isConnected = true
        } else if type == "message_deleted" {
            if let delId = json["message_id"] as? String {
                self.deletedMessageId = delId
            }
        } else if type == "workflow_update" {
            if let event = try? JSONDecoder().decode(WorkflowEvent.self, from: data) {
                self.latestWorkflowEvent = event
            }
        }
    }

    public func sendMessage(target: String, sessionId: String? = nil, text: String, imageBase64: String? = nil) {
        var payload: [String: Any] = [
            "type": "send",
            "target": target,
            "message": text
        ]
        if let sid = sessionId, !sid.isEmpty {
            payload["session_id"] = sid
        }
        if let img = imageBase64 {
            payload["image_base64"] = img
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        webSocketTask?.send(.string(jsonString)) { _ in }
    }

    public func sendDeleteMessage(messageId: String, target: String, sessionId: String? = nil) {
        var payload: [String: Any] = [
            "type": "delete_message",
            "message_id": messageId,
            "target": target
        ]
        if let sid = sessionId, !sid.isEmpty {
            payload["session_id"] = sid
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        webSocketTask?.send(.string(jsonString)) { _ in }
    }

    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.webSocketTask?.sendPing { _ in }
            }
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
}
