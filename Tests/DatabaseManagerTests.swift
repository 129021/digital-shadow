import XCTest
@testable import DigitalShadow

final class DatabaseManagerTests: XCTestCase {
    var dbPath: String!

    override func setUp() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).db")
        dbPath = tmp.path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    func testCreateTables() throws {
        let db = try DatabaseManager(path: dbPath)
        let tables = try db.listTables()
        XCTAssertTrue(tables.contains("events"))
        XCTAssertTrue(tables.contains("sessions"))
    }
}
