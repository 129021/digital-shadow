import XCTest
@testable import DigitalShadow

final class LLMClientTests: XCTestCase {
    func testBuildPrompt() {
        let client = LLMClient(config: AppConfig(apiKey: "test"))
        let sessions = [
            ActivitySession(startTime: Date(), endTime: Date().addingTimeInterval(1800),
                            appGroup: ["VS Code"], title: "编写 auth.ts"),
        ]
        let prompt = client.buildSummaryPrompt(sessions: sessions, period: "最近 30 分钟")
        XCTAssertTrue(prompt.contains("auth.ts"))
        XCTAssertTrue(prompt.contains("DigitalShadow"))
        XCTAssertTrue(prompt.contains("JSON"))
    }

    func testParseResponse() throws {
        let client = LLMClient(config: AppConfig(apiKey: "test"))
        let json = """
        {
          "sessions": [
            {"title": "代码开发", "category": "development", "summary": "编写认证模块"},
            {"title": "浏览文档", "category": "research", "summary": "查阅 API 文档"}
          ],
          "narrative": "上午专注于认证模块开发，期间查阅了相关文档。"
        }
        """
        let result = try client.parseSummaryResponse(json.data(using: .utf8)!)
        XCTAssertEqual(result.sessions.count, 2)
        XCTAssertEqual(result.sessions[0].category, "development")
        XCTAssertTrue(result.narrative.contains("认证"))
    }

    func testBuildEndpointOpenAI() {
        let config = AppConfig(llmProvider: .openai, apiKey: "sk-test", modelName: "gpt-4o-mini")
        let client = LLMClient(config: config)
        let req = client.buildRequest(prompt: "test")
        XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }

    func testBuildEndpointAnthropic() {
        let config = AppConfig(llmProvider: .anthropic, apiKey: "sk-ant-test", modelName: "claude-haiku-4-5-20251001")
        let client = LLMClient(config: config)
        let req = client.buildRequest(prompt: "test")
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
    }
}
