import XCTest
@testable import DigitalShadow

final class LogWriterTests: XCTestCase {
    func testGenerateDailyLog() throws {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        let sessions = [
            ActivitySession(startTime: base.addingTimeInterval(3600),
                            endTime: base.addingTimeInterval(6300),
                            appGroup: ["VS Code", "Terminal"],
                            title: "编写 login.ts"),
            ActivitySession(startTime: base.addingTimeInterval(6300),
                            endTime: base.addingTimeInterval(7200),
                            appGroup: ["Chrome"],
                            title: "浏览 Twitter"),
        ]
        let logWriter = LogWriter()
        let md = logWriter.generateDailyLog(date: base, sessions: sessions)

        XCTAssertTrue(md.contains("# \(logWriter.dateString(base)) 日志"))
        XCTAssertTrue(md.contains("编写 login.ts"))
        XCTAssertTrue(md.contains("浏览 Twitter"))
        XCTAssertTrue(md.contains("|"))
    }

    func testGenerateSummaryLog() throws {
        let logWriter = LogWriter()
        let sessions = [
            ActivitySession(startTime: Date().addingTimeInterval(-7200),
                            endTime: Date().addingTimeInterval(-3600),
                            appGroup: ["Chrome"], title: "代码评审",
                            summary: "审查了 PR #42 中关于认证模块的变更",
                            category: "code_review"),
        ]
        let md = logWriter.generateSummaryLog(sessions: sessions, period: "最近 2 小时")
        XCTAssertTrue(md.contains("代码评审"))
        XCTAssertTrue(md.contains("PR #42"))
    }
}
