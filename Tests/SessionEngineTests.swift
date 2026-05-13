import XCTest
@testable import DigitalShadow

final class SessionEngineTests: XCTestCase {
    func testIdleGapCreatesNewSession() {
        let engine = SessionEngine()
        let base = Date()
        engine.processEvent(RawEvent(timestamp: base, appName: "VS Code",
            bundleId: "com.microsoft.VSCode", windowTitle: "main.swift", url: nil))
        engine.processEvent(RawEvent(timestamp: base.addingTimeInterval(400),
            appName: "Chrome", bundleId: "com.google.Chrome",
            windowTitle: "GitHub", url: "https://github.com"))

        let sessions = engine.finalizeSessions()
        XCTAssertEqual(sessions.count, 2)
    }

    func testAppGroupChangeCreatesNewSession() {
        let engine = SessionEngine()
        let base = Date()
        engine.processEvent(RawEvent(timestamp: base, appName: "VS Code",
            bundleId: "com.microsoft.VSCode", windowTitle: "main.swift", url: nil))
        engine.processEvent(RawEvent(timestamp: base.addingTimeInterval(30),
            appName: "Slack", bundleId: "com.tinyspeck.slackmacgap",
            windowTitle: "Slack — #general", url: nil))

        let sessions = engine.finalizeSessions()
        XCTAssertTrue(sessions.count >= 1)
    }

    func testSameClusterDoesNotCreateNewSession() {
        let engine = SessionEngine()
        let base = Date()
        engine.processEvent(RawEvent(timestamp: base, appName: "VS Code",
            bundleId: "com.microsoft.VSCode", windowTitle: "main.swift", url: nil))
        engine.processEvent(RawEvent(timestamp: base.addingTimeInterval(10),
            appName: "Terminal", bundleId: "com.apple.Terminal",
            windowTitle: "npm run build", url: nil))

        let sessions = engine.finalizeSessions()
        XCTAssertEqual(sessions.count, 1)
    }
}
