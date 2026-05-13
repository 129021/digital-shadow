import XCTest
@testable import DigitalShadow

final class EventStoreTests: XCTestCase {
    var db: DatabaseManager!
    var store: EventStore!
    var dbPath: String!

    override func setUp() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).db")
        dbPath = tmp.path
        db = try DatabaseManager(path: dbPath)
        store = EventStore(db: db)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    func testInsertEvent() throws {
        let event = RawEvent(
            timestamp: Date(),
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            windowTitle: "GitHub PR #42",
            url: "https://github.com/org/repo/pull/42",
            appCategory: .browser
        )
        try store.insertEvent(event)
        XCTAssertEqual(event.id, 1)
    }

    func testQueryEventsInRange() throws {
        let base = Date()
        for i in 0..<5 {
            var e = RawEvent(
                timestamp: base.addingTimeInterval(TimeInterval(i * 60)),
                appName: "TestApp",
                bundleId: "com.test.app",
                windowTitle: "Window \(i)",
                url: nil,
                appCategory: .unknown
            )
            try store.insertEvent(e)
        }
        let results = try store.queryEvents(
            from: base.addingTimeInterval(60),
            to: base.addingTimeInterval(180)
        )
        XCTAssertEqual(results.count, 2)
    }

    func testInsertSession() throws {
        let session = ActivitySession(
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            appGroup: ["Chrome", "VS Code"],
            title: "Code review"
        )
        try store.insertSession(session)
        XCTAssertEqual(session.id, 1)
    }

    func testQuerySessionsForDate() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let s1 = ActivitySession(startTime: today.addingTimeInterval(3600),
                                  endTime: today.addingTimeInterval(7200),
                                  appGroup: ["Chrome"], title: "S1")
        let s2 = ActivitySession(startTime: today.addingTimeInterval(-86400),
                                  endTime: today.addingTimeInterval(-82800),
                                  appGroup: ["VS Code"], title: "S2")
        try store.insertSession(s1)
        try store.insertSession(s2)

        let results = try store.querySessions(for: today)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "S1")
    }
}
