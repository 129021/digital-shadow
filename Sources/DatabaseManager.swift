import Foundation
import SQLite3

final class DatabaseManager {
    private var db: OpaquePointer?
    let path: String

    init(path: String) throws {
        self.path = path
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw DatabaseError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        try createSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            app_name TEXT NOT NULL,
            bundle_id TEXT NOT NULL,
            window_title TEXT NOT NULL DEFAULT '',
            url TEXT,
            duration_ms INTEGER NOT NULL DEFAULT 0,
            app_category TEXT NOT NULL DEFAULT 'unknown'
        );
        CREATE TABLE IF NOT EXISTS sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            app_group TEXT NOT NULL DEFAULT '[]',
            title TEXT NOT NULL DEFAULT '',
            summary TEXT,
            category TEXT,
            merged_into INTEGER
        );
        CREATE INDEX IF NOT EXISTS idx_events_ts ON events(timestamp);
        CREATE INDEX IF NOT EXISTS idx_sessions_start ON sessions(start_time);
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.schemaFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func listTables() throws -> [String] {
        var tables: [String] = []
        let sql = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            tables.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return tables
    }

    var raw: OpaquePointer? { db }

    enum DatabaseError: Error {
        case openFailed(String), schemaFailed(String), queryFailed(String)
    }
}
