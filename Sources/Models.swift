import Foundation

enum AppCategory: String, Codable, CaseIterable {
    case browser, editor, terminal, communication
    case writing, design, entertainment
    case productivity, finance, unknown
}

struct RawEvent: Codable {
    var id: Int64 = 0
    let timestamp: Date
    let appName: String
    let bundleId: String
    let windowTitle: String
    let url: String?
    var durationMs: Int64 = 0
    var appCategory: AppCategory = .unknown
}

struct ActivitySession: Codable {
    var id: Int64 = 0
    let startTime: Date
    let endTime: Date
    let appGroup: [String]
    var title: String = ""
    var summary: String?
    var category: String?
    var mergedInto: Int64?
}

enum LLMProvider: String, Codable, CaseIterable {
    case openai, anthropic, custom
}

enum SummaryFrequency: String, Codable, CaseIterable {
    case fourHours = "4h", eightHours = "8h"
    case daily = "1d", threeDays = "3d"
}

struct AppConfig: Codable {
    var llmProvider: LLMProvider = .openai
    var apiKey: String = ""
    var apiBaseURL: String = ""
    var modelName: String = "gpt-4o-mini"
    var summaryFrequency: SummaryFrequency = .daily
    var isPaused: Bool = false
    var videoCaptionMinDurationSec: Int = 60
}
