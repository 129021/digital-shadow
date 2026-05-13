import Foundation

struct SummaryResult: Codable {
    struct SessionResult: Codable {
        var title: String
        var category: String
        var summary: String
    }
    var sessions: [SessionResult]
    var narrative: String
}

final class LLMClient {
    private let config: AppConfig
    private let decoder = JSONDecoder()

    init(config: AppConfig) {
        self.config = config
    }

    func buildSummaryPrompt(sessions: [ActivitySession], period: String) -> String {
        let sessionList = sessions.enumerated().map { (i, s) in
            let start = ISO8601DateFormatter().string(from: s.startTime)
            let end = ISO8601DateFormatter().string(from: s.endTime)
            return """
            会话 \(i+1):
              时间段: \(start) ~ \(end)
              涉及应用: \(s.appGroup.joined(separator: ", "))
              原始描述: \(s.title)
            """
        }.joined(separator: "\n\n")

        return """
        你是一个客观的第三方观察者（DigitalShadow），负责根据用户电脑活动记录生成活动日志。

        以下是用户在过去一段时间内的活动会话记录：

        \(sessionList)

        请分析以上记录，输出以下 JSON 结构（仅输出 JSON，不要其他内容）：

        {
          "sessions": [
            {
              "title": "简洁的活动名称（≤15字）",
              "category": "development|code_review|meeting|writing|research|browsing|entertainment|communication|other",
              "summary": "一句话描述这个会话在做什么（≤50字）"
            }
          ],
          "narrative": "一段 ≤200 字的中文叙事总结，描述这段时间用户主要在做什么、有什么进展"
        }

        注意：
        - 请优先使用中文输出
        - 请关联跨应用的活动（如同时使用编辑器+终端+浏览器，可能是同一个开发任务）
        - 不要评判用户的活动，只做客观描述
        - URL query string 等敏感信息不要出现在输出中
        """
    }

    func buildRequest(prompt: String) -> URLRequest {
        switch config.llmProvider {
        case .openai:
            let url = URL(string: config.apiBaseURL.isEmpty
                ? "https://api.openai.com/v1/chat/completions"
                : "\(config.apiBaseURL)/v1/chat/completions")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = [
                "model": config.modelName,
                "messages": [
                    ["role": "user", "content": prompt]
                ],
                "temperature": 0.3,
                "max_tokens": 1000,
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            return req

        case .anthropic:
            let url = URL(string: config.apiBaseURL.isEmpty
                ? "https://api.anthropic.com/v1/messages"
                : "\(config.apiBaseURL)/v1/messages")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = [
                "model": config.modelName,
                "max_tokens": 1000,
                "messages": [
                    ["role": "user", "content": prompt]
                ],
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            return req

        case .custom:
            let url = URL(string: "\(config.apiBaseURL)/v1/chat/completions")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = [
                "model": config.modelName,
                "messages": [
                    ["role": "user", "content": prompt]
                ],
                "temperature": 0.3,
                "max_tokens": 1000,
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            return req
        }
    }

    func parseSummaryResponse(_ data: Data) throws -> SummaryResult {
        let text = String(data: data, encoding: .utf8) ?? ""
        let jsonStr = extractJSON(from: text)
        guard let jsonData = jsonStr.data(using: .utf8) else {
            throw LLMError.parseFailed
        }
        return try decoder.decode(SummaryResult.self, from: jsonData)
    }

    func callLLM(prompt: String) async throws -> String {
        let req = buildRequest(prompt: prompt)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.apiError(body)
        }
        switch config.llmProvider {
        case .openai, .custom:
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw LLMError.parseFailed
            }
            return content
        case .anthropic:
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String else {
                throw LLMError.parseFailed
            }
            return text
        }
    }

    private func extractJSON(from text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            return String(cleaned[start...end])
        }
        return cleaned
    }

    enum LLMError: Error {
        case apiError(String), parseFailed
    }
}
