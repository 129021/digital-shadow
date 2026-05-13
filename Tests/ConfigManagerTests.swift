import XCTest
@testable import DigitalShadow

final class ConfigManagerTests: XCTestCase {
    var configPath: String!

    override func setUp() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_config_\(UUID().uuidString).json")
        configPath = tmp.path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: configPath)
    }

    func testLoadDefaultsWhenNoFile() throws {
        let mgr = ConfigManager(path: configPath)
        let config = try mgr.load()
        XCTAssertEqual(config.llmProvider, .openai)
        XCTAssertEqual(config.summaryFrequency, .daily)
        XCTAssertFalse(config.isPaused)
    }

    func testSaveAndLoadRoundtrip() throws {
        let mgr = ConfigManager(path: configPath)
        var config = AppConfig()
        config.llmProvider = .anthropic
        config.apiKey = "sk-test"
        config.summaryFrequency = .eightHours
        try mgr.save(config)

        let loaded = try mgr.load()
        XCTAssertEqual(loaded.llmProvider, .anthropic)
        XCTAssertEqual(loaded.apiKey, "sk-test")
        XCTAssertEqual(loaded.summaryFrequency, .eightHours)
    }
}
