import Foundation

public class APIService {
    public static let shared = APIService()
    public var baseURL: String = "http://192.168.31.188:31188"

    private init() {}

    public func updateEndpoint(host: String, port: Int) {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            self.baseURL = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        } else if trimmed.contains(".") && !trimmed.contains(":") && !trimmed.allSatisfy({ $0.isNumber || $0 == "." }) {
            // 是公网域名（如 ai.yourdomain.com 或 trycloudflare.com）
            self.baseURL = "https://\(trimmed)"
        } else {
            // 纯 IP 或 localhost
            self.baseURL = "http://\(trimmed):\(port)"
        }
    }

    public func fetchSessions(target: String) async throws -> SessionsResponse {
        guard let url = URL(string: "\(baseURL)/api/sessions?target=\(target)") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SessionsResponse.self, from: data)
    }

    public func fetchHistory(target: String, sessionId: String? = nil) async throws -> [ChatMessage] {
        var urlString = "\(baseURL)/api/history?target=\(target)"
        if let sid = sessionId {
            urlString += "&session_id=\(sid)"
        }
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([ChatMessage].self, from: data)
    }

    public func fetchAppStatus(target: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/app_status?target=\(target)") else {
            return false
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let running = json["running"] as? Bool {
            return running
        }
        return false
    }

    public func fetchAllAppStatus() async -> [String: Bool] {
        guard let url = URL(string: "\(baseURL)/api/all_app_status") else {
            return [:]
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] {
                return map
            }
        } catch {
            return [:]
        }
        return [:]
    }

    public func launchApp(target: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/launch_app") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["target": target]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    public func renameSession(target: String, sessionId: String, newTitle: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/rename_session") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["target": target, "session_id": sessionId, "new_title": newTitle]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    public func archiveSession(target: String, sessionId: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/archive_session") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["target": target, "session_id": sessionId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    public func deleteSession(target: String, sessionId: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/delete_session") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["target": target, "session_id": sessionId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    public func newSession(target: String, project: String? = nil) async -> (Bool, String?) {
        guard let url = URL(string: "\(baseURL)/api/new_session") else { return (false, nil) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: String] = ["target": target]
        if let p = project, !p.isEmpty {
            payload["project"] = p
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return (false, nil) }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String, status == "ok" {
                let sid = json["session_id"] as? String
                return (true, sid)
            }
            return (false, nil)
        } catch {
            return (false, nil)
        }
    }

    public func fetchUsageStats(force: Bool = false) async throws -> UsageData {
        guard let url = URL(string: "\(baseURL)/api/usage?force=\(force)") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(UsageResponse.self, from: data)
        if let usage = response.data {
            return usage
        }
        throw URLError(.cannotParseResponse)
    }

    public func sendMessage(target: String, sessionId: String? = nil, text: String, imageBase64: String? = nil) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/send") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "target": target,
            "message": text
        ]
        if let sid = sessionId, !sid.isEmpty {
            payload["session_id"] = sid
        }
        if let img = imageBase64 {
            payload["image_base64"] = img
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
