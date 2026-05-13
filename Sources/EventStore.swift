import Foundation
import SQLite3

final class EventStore {
    private let db: DatabaseManager
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(db: DatabaseManager) { self.db = db }

    func insertEvent(_ event: RawEvent) throws -> Int64 {
        try db.withRaw { raw in
            let sql = """
            INSERT INTO events (timestamp, app_name, bundle_id, window_title, url, duration_ms, app_category)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(raw, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.insertFailed
            }
            defer { sqlite3_finalize(stmt) }

            let ts = isoFormatter.string(from: event.timestamp)
            bind(stmt, idx: 1, value: ts)
            bind(stmt, idx: 2, value: event.appName)
            bind(stmt, idx: 3, value: event.bundleId)
            bind(stmt, idx: 4, value: event.windowTitle)
            bind(stmt, idx: 5, value: event.url)
            sqlite3_bind_int64(stmt, 6, event.durationMs)
            bind(stmt, idx: 7, value: event.appCategory.rawValue)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StoreError.insertFailed
            }
            return sqlite3_last_insert_rowid(raw)
        }
    }

    func queryEvents(from: Date, to: Date) throws -> [RawEvent] {
        try db.withRaw { raw in
            let sql = "SELECT * FROM events WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(raw, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.queryFailed
            }
            defer { sqlite3_finalize(stmt) }

            bind(stmt, idx: 1, value: isoFormatter.string(from: from))
            bind(stmt, idx: 2, value: isoFormatter.string(from: to))

            return parseEvents(stmt)
        }
    }

    func insertSession(_ session: ActivitySession) throws -> Int64 {
        try db.withRaw { raw in
            let sql = """
            INSERT INTO sessions (start_time, end_time, app_group, title, summary, category, merged_into)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(raw, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.insertFailed
            }
            defer { sqlite3_finalize(stmt) }

            bind(stmt, idx: 1, value: isoFormatter.string(from: session.startTime))
            bind(stmt, idx: 2, value: isoFormatter.string(from: session.endTime))
            bind(stmt, idx: 3, value: jsonString(session.appGroup))
            bind(stmt, idx: 4, value: session.title)
            bind(stmt, idx: 5, value: session.summary)
            bind(stmt, idx: 6, value: session.category)
            if let merged = session.mergedInto { sqlite3_bind_int64(stmt, 7, merged) }
            else { sqlite3_bind_null(stmt, 7) }

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StoreError.insertFailed
            }
            return sqlite3_last_insert_rowid(raw)
        }
    }

    func querySessions(for date: Date) throws -> [ActivitySession] {
        try db.withRaw { raw in
            let cal = Calendar.current
            let start = cal.startOfDay(for: date)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let sql = "SELECT * FROM sessions WHERE start_time >= ? AND start_time < ? ORDER BY start_time"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(raw, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.queryFailed
            }
            defer { sqlite3_finalize(stmt) }

            bind(stmt, idx: 1, value: isoFormatter.string(from: start))
            bind(stmt, idx: 2, value: isoFormatter.string(from: end))
            return parseSessions(stmt)
        }
    }

    // MARK: - Helpers

    private func bind(_ stmt: OpaquePointer?, idx: Int32, value: String?) {
        if let v = value {
            sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func jsonString(_ array: [String]) -> String {
        let data = try! JSONEncoder().encode(array)
        return String(data: data, encoding: .utf8)!
    }

    private func parseEvents(_ stmt: OpaquePointer?) -> [RawEvent] {
        var results: [RawEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(RawEvent(
                id: sqlite3_column_int64(stmt, 0),
                timestamp: isoFormatter.date(from: col(stmt, 1) ?? "") ?? Date(),
                appName: col(stmt, 2) ?? "",
                bundleId: col(stmt, 3) ?? "",
                windowTitle: col(stmt, 4) ?? "",
                url: col(stmt, 5),
                durationMs: sqlite3_column_int64(stmt, 6),
                appCategory: AppCategory(rawValue: col(stmt, 7) ?? "unknown") ?? .unknown
            ))
        }
        return results
    }

    private func parseSessions(_ stmt: OpaquePointer?) -> [ActivitySession] {
        var results: [ActivitySession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let appGroupJson = col(stmt, 3) ?? "[]"
            let appGroup = (try? JSONDecoder().decode([String].self,
                              from: appGroupJson.data(using: .utf8)!)) ?? []
            results.append(ActivitySession(
                id: sqlite3_column_int64(stmt, 0),
                startTime: isoFormatter.date(from: col(stmt, 1) ?? "") ?? Date(),
                endTime: isoFormatter.date(from: col(stmt, 2) ?? "") ?? Date(),
                appGroup: appGroup,
                title: col(stmt, 4) ?? "",
                summary: col(stmt, 5),
                category: col(stmt, 6),
                mergedInto: sqlite3_column_type(stmt, 7) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(stmt, 7)
            ))
        }
        return results
    }

    private func col(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard sqlite3_column_type(stmt, idx) != SQLITE_NULL else { return nil }
        return String(cString: sqlite3_column_text(stmt, idx))
    }

    enum StoreError: Error {
        case insertFailed, queryFailed
    }
}
