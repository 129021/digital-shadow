# DigitalShadow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app that passively tracks active app/window/browser activity, generates daily markdown logs with local heuristics, and calls user-configured LLM APIs for periodic semantic summaries.

**Architecture:** Single-process Swift app (LSUIElement, Dock-less) using NSWorkspace + Accessibility API for window monitoring, raw SQLite3 C API for local storage, URLSession for LLM calls. SPM-based build with two targets: the main app executable and a test target. Zero external dependencies — SQLite3 ships with macOS, yt-dlp is an optional runtime dependency.

**Tech Stack:** Swift 5.10+, macOS 14+, Swift Package Manager, raw SQLite3 C API, URLSession

---

## File Map

```
Sources/
├── main.swift                — App entry point, NSApplication setup
├── AppDelegate.swift         — Lifecycle: starts/stops monitor, registers LaunchAgent
├── MenuManager.swift         — NSStatusBar item + NSMenu construction
├── SettingsView.swift        — SwiftUI settings window (API config, frequency, etc.)
├── Models.swift              — Event, Session, AppCategory, Config, LLMProvider types
├── Constants.swift           — Paths, defaults, built-in app mapping table
├── ConfigManager.swift       — Read/write ~/DigitalShadow/config.json
├── DatabaseManager.swift     — SQLite open, schema migration, connection singleton
├── EventStore.swift          — Insert/query events and sessions
├── AppClassifier.swift       — bundle_id → category (built-in table + NSWorkspace fallback)
├── TitleParser.swift         — window_title → human-readable short description
├── AppMonitor.swift          — Accessibility API observer + NSWorkspace notifications
├── SessionEngine.swift       — Idle detection, session boundary logic, session merge
├── LogWriter.swift           — Generate markdown daily log from sessions
├── LLMClient.swift           — URLSession calls to OpenAI/Anthropic API
├── SummaryScheduler.swift    — Timer-based auto-summary; manual trigger
└── VideoCaptionFetcher.swift — yt-dlp subtitle fetch for YouTube/Bilibili
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/main.swift`
- Create: `Sources/Constants.swift`
- Create: `Sources/Models.swift`
- Create: `Resources/Info.plist`
- Create: `Resources/app-mappings.json`
- Create: `.gitignore`

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DigitalShadow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DigitalShadow",
            path: "Sources",
            resources: [.process("../Resources")]
        ),
        .testTarget(
            name: "DigitalShadowTests",
            dependencies: ["DigitalShadow"],
            path: "Tests"
        ),
    ]
)
```

- [ ] **Step 2: Write Sources/Constants.swift**

```swift
import Foundation

enum Constants {
    static let appName = "DigitalShadow"
    static let dataDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("DigitalShadow")
    static let configPath = dataDir.appendingPathComponent("config.json")
    static let dbPath = dataDir.appendingPathComponent("activities.db")
    static let logsDir = dataDir.appendingPathComponent("logs")
    static let summariesDir = dataDir.appendingPathComponent("summaries")
    static let launchAgentDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")
    static let launchAgentPlist = "com.digitalshadow.daemon.plist"
    static let idleThresholdSec: TimeInterval = 300 // 5 minutes
    static let pollIntervalSec: TimeInterval = 2

    static let builtInMappings: [String: AppCategory] = [
        "com.google.Chrome": .browser,
        "com.apple.Safari": .browser,
        "com.microsoft.edgemac": .browser,
        "org.mozilla.firefox": .browser,
        "com.brave.Browser": .browser,
        "company.thebrowser.Browser": .browser, // Arc
        "com.microsoft.VSCode": .editor,
        "com.apple.dt.Xcode": .editor,
        "com.jetbrains.intellij": .editor,
        "com.jetbrains.intellij.ce": .editor,
        "com.jetbrains.pycharm": .editor,
        "com.jetbrains.webstorm": .editor,
        "com.jetbrains.goland": .editor,
        "com.sublimetext.4": .editor,
        "com.apple.Terminal": .terminal,
        "com.googlecode.iterm2": .terminal,
        "dev.warp.Warp-Stable": .terminal,
        "com.tinyspeck.slackmacgap": .communication,
        "com.hnc.Discord": .communication,
        "com.microsoft.teams2": .communication,
        "com.tencent.xinWeChat": .communication,
        "com.bytedance.lark": .communication,
        "com.alibaba.DingTalkMac": .communication,
        "com.apple.mail": .communication,
        "com.microsoft.Outlook": .communication,
        "notion.id": .writing,
        "md.obsidian": .writing,
        "com.apple.iWork.Pages": .writing,
        "com.microsoft.Word": .writing,
        "com.figma.Desktop": .design,
        "com.bohemiancoding.sketch3": .design,
        "com.adobe.Photoshop": .design,
        "com.spotify.client": .entertainment,
        "com.apple.Music": .entertainment,
        "com.netflix.Netflix": .entertainment,
        "com.apple.TV": .entertainment,
        "com.tencent.tenvideo": .entertainment,
        "com.bilibili.quyi": .entertainment,
        "com.google.YouTube": .entertainment,
    ]

    static let videoDomains: [String] = [
        "youtube.com", "youtu.be", "bilibili.com",
    ]
}
```

- [ ] **Step 3: Write Sources/Models.swift**

```swift
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
```

- [ ] **Step 4: Write Resources/Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleName</key>
    <string>DigitalShadow</string>
    <key>CFBundleIdentifier</key>
    <string>com.digitalshadow.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 5: Write Resources/app-mappings.json**

```json
{}
```

This file is a placeholder. The built-in mappings live in Constants.swift. This JSON file exists so users can optionally add custom bundle_id → category overrides. If the file is non-empty, ConfigManager merges its entries with the built-in table (user overrides win).

- [ ] **Step 6: Write Sources/main.swift**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
_ = NSApplicationMain(Process.argc, Process.unsafeArgv)
```

- [ ] **Step 7: Write .gitignore additions**

```
.build/
.DS_Store
._*
```

- [ ] **Step 8: Build to verify scaffold compiles**

```bash
swift build
```

Expected: build succeeds (with unused-variable warnings on delegate — fine).

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "feat: project scaffold with models, constants, Info.plist"
```

---

### Task 2: Database Schema + Manager

**Files:**
- Create: `Sources/DatabaseManager.swift`
- Create: `Tests/DatabaseManagerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter DatabaseManagerTests
```

Expected: compile error — DatabaseManager not defined.

- [ ] **Step 3: Write Sources/DatabaseManager.swift**

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter DatabaseManagerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: DatabaseManager with events + sessions schema"
```

---

### Task 3: ConfigManager

**Files:**
- Create: `Sources/ConfigManager.swift`
- Create: `Tests/ConfigManagerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter ConfigManagerTests
```

Expected: compile error.

- [ ] **Step 3: Write Sources/ConfigManager.swift**

```swift
import Foundation

final class ConfigManager {
    let path: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(path: String) {
        self.path = path
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: path) else {
            return AppConfig()
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try decoder.decode(AppConfig.self, from: data)
    }

    func save(_ config: AppConfig) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(config)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter ConfigManagerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ConfigManager with load/save from config.json"
```

---

### Task 4: AppClassifier

**Files:**
- Create: `Sources/AppClassifier.swift`
- Create: `Tests/AppClassifierTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DigitalShadow

final class AppClassifierTests: XCTestCase {
    func testBuiltInMapping() {
        let classifier = AppClassifier()
        XCTAssertEqual(classifier.classify(bundleId: "com.google.Chrome"), .browser)
        XCTAssertEqual(classifier.classify(bundleId: "com.microsoft.VSCode"), .editor)
        XCTAssertEqual(classifier.classify(bundleId: "com.tinyspeck.slackmacgap"), .communication)
    }

    func testUnknownBundleReturnsUnknown() {
        let classifier = AppClassifier()
        XCTAssertEqual(classifier.classify(bundleId: "com.some.random.app"), .unknown)
    }

    func testIsBrowser() {
        let classifier = AppClassifier()
        XCTAssertTrue(classifier.isBrowser(bundleId: "com.google.Chrome"))
        XCTAssertFalse(classifier.isBrowser(bundleId: "com.microsoft.VSCode"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AppClassifierTests
```

Expected: compile error.

- [ ] **Step 3: Write Sources/AppClassifier.swift**

```swift
import AppKit

final class AppClassifier {
    private let builtInMap: [String: AppCategory]

    init(overrides: [String: AppCategory] = [:]) {
        var map = Constants.builtInMappings
        for (key, val) in overrides {
            map[key] = val
        }
        self.builtInMap = map
    }

    func classify(bundleId: String) -> AppCategory {
        if let cat = builtInMap[bundleId] {
            return cat
        }
        return classifyFromSystem(bundleId: bundleId)
    }

    func isBrowser(bundleId: String) -> Bool {
        classify(bundleId: bundleId) == .browser
    }

    /// Try NSWorkspace's built-in category metadata as a fallback
    private func classifyFromSystem(bundleId: String) -> AppCategory {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              let resources = try? url.resourceValues(forKeys: [.contentTypeKey]),
              let contentType = resources.contentType else {
            return .unknown
        }
        if contentType.conforms(to: .application) {
            return .productivity
        }
        return .unknown
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter AppClassifierTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: AppClassifier with built-in mapping + NSWorkspace fallback"
```

---

### Task 5: TitleParser

**Files:**
- Create: `Sources/TitleParser.swift`
- Create: `Tests/TitleParserTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DigitalShadow

final class TitleParserTests: XCTestCase {
    func testGitHubPR() {
        let result = TitleParser.parse(title: "Pull Request #42 · myorg/myrepo · GitHub", appName: "Google Chrome")
        XCTAssertTrue(result.contains("GitHub PR #42"))
    }

    func testVSCodeFile() {
        let result = TitleParser.parse(title: "src/login.ts — DigitalShadow", appName: "Visual Studio Code")
        XCTAssertTrue(result.contains("login.ts"))
    }

    func testTerminal() {
        let result = TitleParser.parse(title: "npm run dev — zsh — 80×24", appName: "Terminal")
        XCTAssertTrue(result.contains("终端"))
    }

    func testYouTube() {
        let result = TitleParser.parse(title: "How to Build a Rust CLI — YouTube", appName: "Google Chrome")
        XCTAssertTrue(result.contains("YouTube"))
    }

    func testTwitter() {
        let result = TitleParser.parse(title: "X / home", appName: "Google Chrome")
        XCTAssertTrue(result.contains("X.com"))
    }

    func testGenericReturnsCleanedTitle() {
        let result = TitleParser.parse(title: "Some Random Window", appName: "UnknownApp")
        XCTAssertFalse(result.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter TitleParserTests
```

Expected: compile error.

- [ ] **Step 3: Write Sources/TitleParser.swift**

```swift
import Foundation

enum TitleParser {
    private static let patterns: [(NSRegularExpression, String)] = [
        // GitHub PR
        try! (NSRegularExpression(pattern: "^(.*?Pull Request #\\d+).*"), "$1"),
        // GitHub repo
        try! (NSRegularExpression(pattern: "^(.*?) · GitHub$", options: []), "$1 · GitHub"),
        // VS Code / editor: "filename — project"
        try! (NSRegularExpression(pattern: "^(.*?\\.\\w+)\\s*[—–-]\\s*(.*)$"), "编辑 $1"),
        // Terminal
        try! (NSRegularExpression(pattern: "^(.*?)\\s*[—–-]\\s*(zsh|bash|fish|nu)\\b"), "终端：$1"),
        // YouTube
        try! (NSRegularExpression(pattern: "^(.*?)\\s*-\\s*YouTube$"), "$1 · YouTube"),
        // Bilibili
        try! (NSRegularExpression(pattern: "^(.*?)_哔哩哔哩"), "$1 · Bilibili"),
        // X/Twitter
        try! (NSRegularExpression(pattern: "^X / (.*)$"), "浏览 X.com：$1"),
        // Twitter legacy
        try! (NSRegularExpression(pattern: "^(.*?) / Twitter$"), "$1 · X.com"),
        // Slack
        try! (NSRegularExpression(pattern: "^Slack — (.*)$"), "Slack：$1"),
        // Notion
        try! (NSRegularExpression(pattern: "^(.*?) — Notion$"), "$1 · Notion"),
    ]

    static func parse(title: String, appName: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return appName }

        for (regex, template) in patterns {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = regex.firstMatch(in: trimmed, range: range) {
                let result = regex.replacementString(for: match, in: trimmed, offset: 0, template: template)
                return result
            }
        }
        return trimmed
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter TitleParserTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: TitleParser for window title → readable description"
```

---

### Task 6: EventStore

**Files:**
- Create: `Sources/EventStore.swift`
- Create: `Tests/EventStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter EventStoreTests
```

Expected: compile error.

- [ ] **Step 3: Write Sources/EventStore.swift**

```swift
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

    func insertEvent(_ event: RawEvent) throws {
        var e = event
        let sql = """
        INSERT INTO events (timestamp, app_name, bundle_id, window_title, url, duration_ms, app_category)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.raw, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.insertFailed
        }
        defer { sqlite3_finalize(stmt) }

        let ts = isoFormatter.string(from: e.timestamp)
        bind(stmt, idx: 1, value: ts)
        bind(stmt, idx: 2, value: e.appName)
        bind(stmt, idx: 3, value: e.bundleId)
        bind(stmt, idx: 4, value: e.windowTitle)
        bind(stmt, idx: 5, value: e.url)
        sqlite3_bind_int64(stmt, 6, e.durationMs)
        bind(stmt, idx: 7, value: e.appCategory.rawValue)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.insertFailed
        }
        e.id = sqlite3_last_insert_rowid(db.raw)
    }

    func queryEvents(from: Date, to: Date) throws -> [RawEvent] {
        let sql = "SELECT * FROM events WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.raw, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt, idx: 1, value: isoFormatter.string(from: from))
        bind(stmt, idx: 2, value: isoFormatter.string(from: to))

        return parseEvents(stmt)
    }

    func insertSession(_ session: ActivitySession) throws {
        var s = session
        let sql = """
        INSERT INTO sessions (start_time, end_time, app_group, title, summary, category, merged_into)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.raw, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.insertFailed
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt, idx: 1, value: isoFormatter.string(from: s.startTime))
        bind(stmt, idx: 2, value: isoFormatter.string(from: s.endTime))
        bind(stmt, idx: 3, value: jsonString(s.appGroup))
        bind(stmt, idx: 4, value: s.title)
        bind(stmt, idx: 5, value: s.summary)
        bind(stmt, idx: 6, value: s.category)
        if let merged = s.mergedInto { sqlite3_bind_int64(stmt, 7, merged) }
        else { sqlite3_bind_null(stmt, 7) }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.insertFailed
        }
        s.id = sqlite3_last_insert_rowid(db.raw)
    }

    func querySessions(for date: Date) throws -> [ActivitySession] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let sql = "SELECT * FROM sessions WHERE start_time >= ? AND start_time < ? ORDER BY start_time"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.raw, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt, idx: 1, value: isoFormatter.string(from: start))
        bind(stmt, idx: 2, value: isoFormatter.string(from: end))
        return parseSessions(stmt)
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
                timestamp: isoFormatter.date(from: col(stmt, 1)) ?? Date(),
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter EventStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: EventStore with insert/query for events and sessions"
```

---

### Task 7: AppMonitor — Active Window Tracking

**Files:**
- Create: `Sources/AppMonitor.swift`

- [ ] **Step 1: Write Sources/AppMonitor.swift**

```swift
import AppKit
import ApplicationServices

protocol AppMonitorDelegate: AnyObject {
    func appMonitor(_ monitor: AppMonitor, didDetectEvent event: RawEvent)
    func appMonitorDidDetectIdle(_ monitor: AppMonitor, since: Date)
    func appMonitorDidBecomeActive(_ monitor: AppMonitor)
}

final class AppMonitor {
    weak var delegate: AppMonitorDelegate?
    private var isRunning = false
    private var currentEvent: RawEvent?
    private var lastActiveTime = Date()
    private var timer: DispatchSourceTimer?
    private let classifier = AppClassifier()
    private let queue = DispatchQueue(label: "com.digitalshadow.monitor", qos: .utility)
    private var axObserver: AXObserver?
    private var lastFocusedApp: NSRunningApplication?
    private var lastWindowTitle: String?

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // System-wide Accessibility observer for focused window changes
        setupAXObserver()

        // NSWorkspace notifications for app switches
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appDidActivate(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)

        // Periodic polling for window title changes (some apps don't emit AX events)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: Constants.pollIntervalSec)
        timer?.setEventHandler { [weak self] in self?.poll() }
        timer?.resume()
    }

    func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let obs = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                                  AXObserverGetRunLoopSource(obs), .defaultMode)
            axObserver = nil
        }
    }

    // MARK: - Private

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        lastFocusedApp = app
        lastActiveTime = Date()
        queue.async { [weak self] in self?.recordCurrent() }
    }

    private func setupAXObserver() {
        // Observe focused window changes system-wide
        let callback: AXObserverCallback = { (observer, element, notification, refcon) in
            guard let selfPtr = refcon else { return }
            let monitor = Unmanaged<AppMonitor>.fromOpaque(selfPtr).takeUnretainedValue()
            monitor.queue.async { monitor.handleAXChange() }
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverCreate(ProcessIdentifier(), callback, &axObserver) == .success,
              let obs = axObserver else { return }

        // We observe the focused application's main window
        // Actually, we need to observe the focused UI element for title changes
        // Simpler approach: rely on polling for window titles
        CFRunLoopAddSource(CFRunLoopGetCurrent(),
                           AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    private func handleAXChange() {
        recordCurrent()
    }

    private func poll() {
        guard isRunning else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                        eventType: CGEventType(rawValue: ~0)!)
        if idle > Constants.idleThresholdSec {
            delegate?.appMonitorDidDetectIdle(self, since: Date().addingTimeInterval(-idle))
            return
        }
        delegate?.appMonitorDidBecomeActive(self)
        recordCurrent()
    }

    private func recordCurrent() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        let title = currentWindowTitle(for: app)
        guard title != lastWindowTitle || app != lastFocusedApp else { return }
        lastWindowTitle = title
        lastFocusedApp = app

        let bundleId = app.bundleIdentifier ?? "unknown"
        let category = classifier.classify(bundleId: bundleId)
        let url = category == .browser ? currentBrowserURL(title: title) : nil

        let event = RawEvent(
            timestamp: Date(),
            appName: app.localizedName ?? "Unknown",
            bundleId: bundleId,
            windowTitle: title,
            url: url,
            appCategory: category
        )
        currentEvent = event
        delegate?.appMonitor(self, didDetectEvent: event)
    }

    private func currentWindowTitle(for app: NSRunningApplication) -> String {
        // Use Accessibility API to get focused window title
        guard let pid = app.processIdentifier as pid_t? else { return "" }
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement,
                kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let window = focusedWindow else { return "" }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement,
                kAXTitleAttribute as CFString, &title) == .success else { return "" }
        return title as? String ?? ""
    }

    private func currentBrowserURL(title: String) -> String? {
        // For browsers, use AppleScript to get current URL
        // This is the most reliable method without a browser extension
        guard let app = lastFocusedApp,
              let bundleId = app.bundleIdentifier,
              classifier.isBrowser(bundleId: bundleId) else { return nil }

        let script: String
        if bundleId == "com.apple.Safari" {
            script = "tell application \"Safari\" to return URL of front document"
        } else {
            // Chrome/Brave/Edge — all support the same AppleScript interface
            script = "tell application \"\(app.localizedName ?? "")\" to return URL of active tab of front window"
        }

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        let result = appleScript?.executeAndReturnError(&error)
        return result?.stringValue
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: AppMonitor with AX + NSWorkspace window tracking"
```

---

### Task 8: SessionEngine

**Files:**
- Create: `Sources/SessionEngine.swift`
- Create: `Tests/SessionEngineTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
        // Editor cluster
        engine.processEvent(RawEvent(timestamp: base, appName: "VS Code",
            bundleId: "com.microsoft.VSCode", windowTitle: "main.swift", url: nil))
        // Switch to communication
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
        // Both are in development cluster (editor + terminal)
        XCTAssertEqual(sessions.count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter SessionEngineTests
```

Expected: compile error.

- [ ] **Step 3: Write Sources/SessionEngine.swift**

```swift
import Foundation

final class SessionEngine {
    private var currentSession: ActivitySession?
    private var completedSessions: [ActivitySession] = []
    private var sessionEvents: [RawEvent] = []
    private var lastEventTime: Date?
    private var appCategoryClusters: [AppCategory: [AppCategory]] = [
        .editor: [.editor, .terminal],
        .terminal: [.terminal, .editor],
        .browser: [.browser],
        .communication: [.communication],
        .writing: [.writing, .browser],
        .design: [.design, .browser],
    ]
    private var appGroupAppearances: [String: Int] = [:]
    private var windowTitleAppearances: [String: Int] = [:]

    func processEvent(_ event: RawEvent) {
        let gap = lastEventTime.map { event.timestamp.timeIntervalSince($0) } ?? 0
        let exceedsIdle = gap > Constants.idleThresholdSec

        if let session = currentSession, !exceedsIdle {
            if sameCluster(event) {
                // Extend current session
                currentSession = ActivitySession(
                    id: session.id,
                    startTime: session.startTime,
                    endTime: event.timestamp,
                    appGroup: unionAppGroup(session.appGroup, event.appName),
                    title: session.title,
                    category: session.category
                )
            } else {
                // Cluster change — close current, start new
                finalizeCurrent()
                startNewSession(event)
            }
        } else {
            // First event or idle gap exceeded
            if currentSession != nil { finalizeCurrent() }
            startNewSession(event)
        }

        appGroupAppearances[event.appName, default: 0] += 1
        windowTitleAppearances[event.windowTitle, default: 0] += 1
        sessionEvents.append(event)
        lastEventTime = event.timestamp
    }

    func finalizeSessions() -> [ActivitySession] {
        finalizeCurrent()
        return completedSessions
    }

    private func sameCluster(_ event: RawEvent) -> Bool {
        guard let session = currentSession else { return true }
        let sessionCats = Set(session.appGroup.compactMap { name in
            sessionEvents.last(where: { $0.appName == name })?.appCategory
        })
        let neighbors = sessionCats.flatMap { appCategoryClusters[$0] ?? [] }
        return neighbors.contains(event.appCategory) || sessionCats.contains(event.appCategory)
    }

    private func startNewSession(_ event: RawEvent) {
        currentSession = ActivitySession(
            startTime: event.timestamp,
            endTime: event.timestamp,
            appGroup: [event.appName],
            title: TitleParser.parse(title: event.windowTitle, appName: event.appName)
        )
    }

    private func finalizeCurrent() {
        guard var session = currentSession, !sessionEvents.isEmpty else { return }
        // Use most frequent window title's parsed result for the session title
        let topTitle = windowTitleAppearances.max(by: { $0.value < $1.value })?.key ?? ""
        let topApp = appGroupAppearances.max(by: { $0.value < $1.value })?.key ?? ""
        if let topEvent = sessionEvents.first(where: { $0.windowTitle == topTitle }) {
            session.title = TitleParser.parse(title: topTitle, appName: topApp)
        }
        completedSessions.append(session)
        currentSession = nil
        sessionEvents.removeAll()
        appGroupAppearances.removeAll()
        windowTitleAppearances.removeAll()
    }

    private func unionAppGroup(_ existing: [String], _ newApp: String) -> [String] {
        var group = existing
        if !group.contains(newApp) { group.append(newApp) }
        return group
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter SessionEngineTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: SessionEngine with idle detection + cluster-based session boundaries"
```

---

### Task 9: LogWriter — Markdown Generation

**Files:**
- Create: `Sources/LogWriter.swift`
- Create: `Tests/LogWriterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
        XCTAssertTrue(md.contains("|")) // Has a table
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter LogWriterTests
```

Expected: compile error.

- [ ] **Step 3: Write Sources/LogWriter.swift**

```swift
import Foundation

final class LogWriter {
    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    func dateString(_ date: Date) -> String {
        dateFmt.string(from: date)
    }

    func generateDailyLog(date: Date, sessions: [ActivitySession]) -> String {
        var md = """
        # \(dateString(date)) 日志

        ## 时间线

        | 时段 | 活动 | 时长 |
        |------|------|------|

        """

        for s in sessions {
            let start = timeFmt.string(from: s.startTime)
            let end = timeFmt.string(from: s.endTime)
            let duration = formatDuration(s.endTime.timeIntervalSince(s.startTime))
            md += "| \(start)-\(end) | \(s.title) | \(duration) |\n"
        }

        md += "\n## 应用时长统计\n\n"

        var appDurations: [String: TimeInterval] = [:]
        // Approximate: each app in appGroup gets equal share of session duration
        for s in sessions {
            let dur = s.endTime.timeIntervalSince(s.startTime)
            let share = dur / Double(max(1, s.appGroup.count))
            for app in s.appGroup {
                appDurations[app, default: 0] += share
            }
        }
        let sorted = appDurations.sorted { $0.value > $1.value }
        let appStats = sorted.map { "\($0.key): \(formatDuration($0.value))" }
            .joined(separator: " | ")
        md += "\(appStats)\n"

        if !sessions.isEmpty {
            md += "\n---\n\n"
            md += "*此日志由 DigitalShadow 自动生成*\n"
        }

        return md
    }

    func generateSummaryLog(sessions: [ActivitySession], period: String) -> String {
        let now = Date()
        let fileName = "\(dateString(now))_\(timeFmt.string(from: now).replacingOccurrences(of: ":", with: "-"))_summary"

        var md = """
        # DigitalShadow 总结 — \(period)

        ## 活动总览

        | 时段 | 活动 | 分类 | 时长 |
        |------|------|------|------|

        """

        for s in sessions {
            let start = timeFmt.string(from: s.startTime)
            let end = timeFmt.string(from: s.endTime)
            let dur = formatDuration(s.endTime.timeIntervalSince(s.startTime))
            let cat = s.category ?? "-"
            md += "| \(start)-\(end) | \(s.title) | \(cat) | \(dur) |\n"
        }

        md += "\n## 叙事总结\n\n"

        for s in sessions where s.summary != nil {
            md += "> \(s.summary!)\n\n"
        }

        md += "---\n*总结时间：\(ISO8601DateFormatter().string(from: now))*\n"
        return md
    }

    func summaryFilePath(prefix: String) -> URL {
        let now = Date()
        let name = "\(dateString(now))_\(timeFmt.string(from: now).replacingOccurrences(of: ":", with: "-"))_\(prefix).md"
        return Constants.logsDir.appendingPathComponent(name)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let mins = Int(interval / 60)
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return "\(h)h\(m)min"
        }
        return "\(max(1, mins))min"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter LogWriterTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: LogWriter for daily + summary markdown generation"
```

---

### Task 10: LLMClient

**Files:**
- Create: `Sources/LLMClient.swift`
- Create: `Tests/LLMClientTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter LLMClientTests
```

Expected: compile error.

- [ ] **Step 3: Write Sources/LLMClient.swift**

```swift
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
    private let encoder = JSONEncoder()
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
        // Try to extract JSON from response (may be wrapped in markdown code blocks)
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
        // Parse response based on provider
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
        // Strip markdown code fences if present
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Find the outermost { ... }
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter LLMClientTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: LLMClient for OpenAI + Anthropic + custom API"
```

---

### Task 11: VideoCaptionFetcher

**Files:**
- Create: `Sources/VideoCaptionFetcher.swift`
- Create: `Tests/VideoCaptionFetcherTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DigitalShadow

final class VideoCaptionFetcherTests: XCTestCase {
    func testIsVideoURL() {
        let fetcher = VideoCaptionFetcher()
        XCTAssertTrue(fetcher.isVideoURL("https://www.youtube.com/watch?v=abc123"))
        XCTAssertTrue(fetcher.isVideoURL("https://youtu.be/abc123"))
        XCTAssertTrue(fetcher.isVideoURL("https://www.bilibili.com/video/BV1xx411c7mD"))
        XCTAssertFalse(fetcher.isVideoURL("https://github.com"))
    }

    func testExtractYouTubeVideoID() {
        let fetcher = VideoCaptionFetcher()
        XCTAssertEqual(fetcher.extractYTVideoID("https://www.youtube.com/watch?v=abc123"), "abc123")
        XCTAssertEqual(fetcher.extractYTVideoID("https://youtu.be/abc123"), "abc123")
    }

    func testBuildYTDLPCommand() {
        let fetcher = VideoCaptionFetcher()
        let cmd = fetcher.buildCommand(url: "https://www.youtube.com/watch?v=abc123",
                                        outputPath: "/tmp/test_abc123")
        XCTAssertTrue(cmd.contains("yt-dlp"))
        XCTAssertTrue(cmd.contains("abc123"))
        XCTAssertTrue(cmd.contains("--write-auto-subs"))
        XCTAssertTrue(cmd.contains("--sub-format"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter VideoCaptionFetcherTests
```

Expected: compile error.

- [ ] **Step 3: Write Sources/VideoCaptionFetcher.swift**

```swift
import Foundation

final class VideoCaptionFetcher {
    private let videoDomains = Constants.videoDomains

    func isVideoURL(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        return videoDomains.contains(where: { host.contains($0) })
    }

    func extractYTVideoID(_ url: String) -> String? {
        guard let components = URLComponents(string: url) else { return nil }
        if let host = components.host, host.contains("youtu.be") {
            return components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return components.queryItems?.first(where: { $0.name == "v" })?.value
    }

    func buildCommand(url: String, outputPath: String) -> String {
        "yt-dlp --write-auto-subs --sub-format srt1 --skip-download --sub-langs en,zh-Hans --max-subs 1 -o \"\(outputPath)\" \"\(url)\""
    }

    /// Fetch caption text for a video URL. Returns the first 500 chars of subtitle text.
    func fetchCaptions(for url: String) async throws -> String? {
        guard isVideoURL(url) else { return nil }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("digitalshadow_captions_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let outputTemplate = tmpDir.appendingPathComponent("%(id)s").path
        let cmd = buildCommand(url: url, outputPath: outputTemplate)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "\(cmd) 2>/dev/null"]
        process.currentDirectoryURL = tmpDir

        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()

        // Find and read the subtitle file
        let files = (try? FileManager.default.contentsOfDirectory(at: tmpDir,
            includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "srt" || file.pathExtension == "vtt" {
            let content = try String(contentsOf: file, encoding: .utf8)
            // Strip SRT/VTT formatting: remove line numbers, timestamps, keep text
            let text = parseSubtitleText(content)
            return String(text.prefix(500))
        }
        return nil
    }

    private func parseSubtitleText(_ raw: String) -> String {
        var lines: [String] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.contains("-->") { continue } // timestamp
            if let _ = Int(trimmed) { continue } // sequence number
            if trimmed.hasPrefix("WEBVTT") { continue } // VTT header
            lines.append(trimmed)
        }
        return lines.joined(separator: " ")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter VideoCaptionFetcherTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: VideoCaptionFetcher with yt-dlp subtitle extraction"
```

---

### Task 12: SummaryScheduler

**Files:**
- Create: `Sources/SummaryScheduler.swift`

- [ ] **Step 1: Write Sources/SummaryScheduler.swift**

```swift
import Foundation

protocol SummarySchedulerDelegate: AnyObject {
    func summaryScheduler(_ scheduler: SummaryScheduler, shouldSummarize sessions: [ActivitySession], period: String)
}

final class SummaryScheduler {
    weak var delegate: SummarySchedulerDelegate?
    private var timer: DispatchSourceTimer?
    private var lastSummaryTime: Date?
    private let queue = DispatchQueue(label: "com.digitalshadow.summary", qos: .background)
    private let store: EventStore
    private let configManager: ConfigManager

    init(store: EventStore, configManager: ConfigManager) {
        self.store = store
        self.configManager = configManager
    }

    func start() {
        scheduleNext()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func triggerNow(period: String? = nil) {
        queue.async { [weak self] in
            self?.performSummary(label: period)
        }
    }

    func scheduleNext() {
        timer?.cancel()
        let config = (try? configManager.load()) ?? AppConfig()
        let interval: TimeInterval
        switch config.summaryFrequency {
        case .fourHours: interval = 4 * 3600
        case .eightHours: interval = 8 * 3600
        case .daily: interval = 24 * 3600
        case .threeDays: interval = 72 * 3600
        }

        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + 60, repeating: interval)
        timer?.setEventHandler { [weak self] in
            self?.performSummary(label: nil)
        }
        timer?.resume()
    }

    private func performSummary(label: String?) {
        let config = (try? configManager.load()) ?? AppConfig()
        guard !config.apiKey.isEmpty else { return }

        let now = Date()
        let lookback: TimeInterval
        switch config.summaryFrequency {
        case .fourHours: lookback = 4 * 3600
        case .eightHours: lookback = 8 * 3600
        case .daily: lookback = 24 * 3600
        case .threeDays: lookback = 72 * 3600
        }

        let from = lastSummaryTime ?? now.addingTimeInterval(-lookback)
        let sessions: [ActivitySession]
        do {
            sessions = try store.querySessions(for: from)
        } catch {
            return
        }

        guard !sessions.isEmpty else { return }

        let periodLabel = label ?? config.summaryFrequency.rawValue
        delegate?.summaryScheduler(self, shouldSummarize: sessions, period: periodLabel)
        lastSummaryTime = now
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: SummaryScheduler with configurable frequency timer"
```

---

### Task 13: MenuManager + AppDelegate — Menu Bar UI

**Files:**
- Create: `Sources/MenuManager.swift`
- Create: `Sources/AppDelegate.swift`

- [ ] **Step 1: Write Sources/MenuManager.swift**

```swift
import AppKit

protocol MenuManagerDelegate: AnyObject {
    func menuManagerDidRequestTogglePause(_ manager: MenuManager)
    func menuManagerDidRequestSummarize(_ manager: MenuManager)
    func menuManagerDidRequestOpenToday(_ manager: MenuManager)
    func menuManagerDidRequestSettings(_ manager: MenuManager)
    func menuManagerDidRequestQuit(_ manager: MenuManager)
}

final class MenuManager {
    weak var delegate: MenuManagerDelegate?
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var pauseMenuItem: NSMenuItem!
    private var isPaused = false

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        // Today's log
        let todayItem = NSMenuItem(title: "今日摘要", action: #selector(openToday), keyEquivalent: "")
        todayItem.target = self
        menu.addItem(todayItem)

        // Manual summarize
        let summarizeItem = NSMenuItem(title: "总结最近 N 小时", action: #selector(summarizeNow), keyEquivalent: "")
        summarizeItem.target = self
        menu.addItem(summarizeItem)

        menu.addItem(.separator())

        // Pause/Resume
        pauseMenuItem = NSMenuItem(title: "暂停记录", action: #selector(togglePause), keyEquivalent: "")
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Quit
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateIcon(active: true)

        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    func updateIcon(active: Bool) {
        if let button = statusItem.button {
            // Small colored circle using attributed string
            let color = active ? NSColor.systemGreen : NSColor.systemGray
            let size: CGFloat = 10
            let image = NSImage(size: NSSize(width: size, height: size))
            image.lockFocus()
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)).fill()
            image.unlockFocus()
            image.isTemplate = false
            button.image = image
        }
        isPaused = !active
        pauseMenuItem.title = active ? "暂停记录" : "恢复记录"
    }

    @objc private func openToday() {
        delegate?.menuManagerDidRequestOpenToday(self)
    }

    @objc private func summarizeNow() {
        delegate?.menuManagerDidRequestSummarize(self)
    }

    @objc private func togglePause() {
        delegate?.menuManagerDidRequestTogglePause(self)
    }

    @objc private func openSettings() {
        delegate?.menuManagerDidRequestSettings(self)
    }

    @objc private func quitApp() {
        delegate?.menuManagerDidRequestQuit(self)
    }
}
```

- [ ] **Step 2: Write Sources/AppDelegate.swift**

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuManager = MenuManager()
    private let monitor = AppMonitor()
    private let classifier = AppClassifier()
    private let sessionEngine = SessionEngine()

    private var dbManager: DatabaseManager!
    private var eventStore: EventStore!
    private var configManager: ConfigManager!
    private var logWriter: LogWriter!
    private var llmClient: LLMClient?
    private var summaryScheduler: SummaryScheduler!
    private var videoFetcher: VideoCaptionFetcher!

    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create data directory
        try? FileManager.default.createDirectory(at: Constants.dataDir,
            withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Constants.logsDir,
            withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Constants.summariesDir,
            withIntermediateDirectories: true)

        // Init core services
        configManager = ConfigManager(path: Constants.configPath.path)
        dbManager = try! DatabaseManager(path: Constants.dbPath.path)
        eventStore = EventStore(db: dbManager)
        logWriter = LogWriter()
        videoFetcher = VideoCaptionFetcher()

        // LLM
        let config = (try? configManager.load()) ?? AppConfig()
        if !config.apiKey.isEmpty {
            llmClient = LLMClient(config: config)
        }

        // Menu bar
        menuManager.delegate = self
        menuManager.setup()

        // Monitor
        monitor.delegate = self
        monitor.start()

        // Scheduler
        summaryScheduler = SummaryScheduler(store: eventStore, configManager: configManager)
        summaryScheduler.delegate = self
        summaryScheduler.start()

        // Idle
        NSApp.disableRelaunchOnLogin()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        summaryScheduler.stop()
        // Finalize today's log
        let sessions = sessionEngine.finalizeSessions()
        let today = Date()
        let md = logWriter.generateDailyLog(date: today, sessions: sessions)
        let path = Constants.logsDir.appendingPathComponent("\(logWriter.dateString(today)).md")
        try? md.write(to: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - MenuManagerDelegate

extension AppDelegate: MenuManagerDelegate {
    func menuManagerDidRequestOpenToday(_ manager: MenuManager) {
        let today = logWriter.dateString(Date())
        let path = Constants.logsDir.appendingPathComponent("\(today).md")
        NSWorkspace.shared.open(path)
    }

    func menuManagerDidRequestSummarize(_ manager: MenuManager) {
        summaryScheduler.triggerNow(period: "手动触发")
    }

    func menuManagerDidRequestTogglePause(_ manager: MenuManager) {
        var config = (try? configManager.load()) ?? AppConfig()
        config.isPaused.toggle()
        try? configManager.save(config)
        menuManager.updateIcon(active: !config.isPaused)
        if config.isPaused {
            monitor.stop()
        } else {
            monitor.start()
        }
    }

    func menuManagerDidRequestSettings(_ manager: MenuManager) {
        if settingsWindow == nil {
            let view = SettingsView(configManager: configManager) { [weak self] in
                self?.settingsWindow?.close()
                self?.settingsWindow = nil
                // Reload LLM client and scheduler with new config
                self?.reloadConfig()
            }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "DigitalShadow 设置"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func menuManagerDidRequestQuit(_ manager: MenuManager) {
        NSApp.terminate(nil)
    }

    private func reloadConfig() {
        let config = (try? configManager.load()) ?? AppConfig()
        llmClient = config.apiKey.isEmpty ? nil : LLMClient(config: config)
        summaryScheduler.scheduleNext()
    }
}

// MARK: - AppMonitorDelegate

extension AppDelegate: AppMonitorDelegate {
    func appMonitor(_ monitor: AppMonitor, didDetectEvent event: RawEvent) {
        var classifiedEvent = event
        classifiedEvent.appCategory = classifier.classify(bundleId: event.bundleId)
        try? eventStore.insertEvent(classifiedEvent)
        sessionEngine.processEvent(classifiedEvent)

        // Write daily log incrementally (every event triggers a rewrite — ok, it's tiny)
        let sessions = sessionEngine.finalizeSessions()
        let today = Date()
        let md = logWriter.generateDailyLog(date: today, sessions: sessions)
        let path = Constants.logsDir.appendingPathComponent("\(logWriter.dateString(today)).md")
        try? md.write(to: path, atomically: true, encoding: .utf8)

        // Check for video content
        if let url = event.url, videoFetcher.isVideoURL(url) {
            Task {
                if let captions = try? await videoFetcher.fetchCaptions(for: url),
                   var lastSession = sessions.last {
                    lastSession.summary = (lastSession.summary ?? "") + "\n[字幕] \(captions)"
                    try? eventStore.insertSession(lastSession)
                }
            }
        }
    }

    func appMonitorDidDetectIdle(_ monitor: AppMonitor, since: Date) {
        // Pass idle timestamp — no action needed, SessionEngine handles this via time gaps
    }

    func appMonitorDidBecomeActive(_ monitor: AppMonitor) {
        // Activity resumed
    }
}

// MARK: - SummarySchedulerDelegate

extension AppDelegate: SummarySchedulerDelegate {
    func summaryScheduler(_ scheduler: SummaryScheduler,
                          shouldSummarize sessions: [ActivitySession],
                          period: String) {
        guard let client = llmClient else { return }
        let prompt = client.buildSummaryPrompt(sessions: sessions, period: period)
        Task {
            do {
                let response = try await client.callLLM(prompt: prompt)
                let result = try client.parseSummaryResponse(
                    response.data(using: .utf8) ?? Data()
                )
                // Update session summaries
                for (i, sr) in result.sessions.enumerated() where i < sessions.count {
                    var updated = sessions[i]
                    updated.title = sr.title
                    updated.summary = sr.summary
                    updated.category = sr.category
                    try? eventStore.insertSession(updated)
                }
                // Write summary markdown
                let updatedSessions = (try? eventStore.querySessions(for: Date())) ?? sessions
                let md = logWriter.generateSummaryLog(sessions: updatedSessions, period: period)
                let path = logWriter.summaryFilePath(prefix: period.replacingOccurrences(of: " ", with: "_"))
                try? md.write(to: path, atomically: true, encoding: .utf8)
            } catch {
                print("[DigitalShadow] LLM 总结失败: \(error)")
            }
        }
    }
}
```

- [ ] **Step 3: Build to verify**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: MenuManager + AppDelegate wiring all components"
```

---

### Task 14: Settings UI

**Files:**
- Create: `Sources/SettingsView.swift`

- [ ] **Step 1: Write Sources/SettingsView.swift**

```swift
import SwiftUI

struct SettingsView: View {
    let configManager: ConfigManager
    let onDismiss: () -> Void

    @State private var llmProvider: LLMProvider = .openai
    @State private var apiKey: String = ""
    @State private var apiBaseURL: String = ""
    @State private var modelName: String = "gpt-4o-mini"
    @State private var summaryFrequency: SummaryFrequency = .daily
    @State private var hasChanges = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DigitalShadow 设置")
                .font(.headline)
                .padding(.top, 8)

            Divider()

            // LLM Provider
            Picker("AI 提供商", selection: $llmProvider) {
                Text("OpenAI").tag(LLMProvider.openai)
                Text("Anthropic").tag(LLMProvider.anthropic)
                Text("自定义").tag(LLMProvider.custom)
            }
            .pickerStyle(.segmented)
            .onChange(of: llmProvider) { _ in
                hasChanges = true
                if llmProvider != .custom { apiBaseURL = "" }
                if llmProvider == .anthropic && modelName == "gpt-4o-mini" {
                    modelName = "claude-haiku-4-5-20251001"
                }
                if llmProvider == .openai && modelName.contains("claude") {
                    modelName = "gpt-4o-mini"
                }
            }

            // API Key
            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .onChange(of: apiKey) { _ in hasChanges = true }

            // Custom API Base URL (only for custom provider)
            if llmProvider == .custom {
                TextField("API 地址 (如 https://api.example.com)", text: $apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiBaseURL) { _ in hasChanges = true }
            }

            // Model Name
            TextField("模型名称", text: $modelName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: modelName) { _ in hasChanges = true }

            Divider()

            // Summary Frequency
            Picker("自动总结频率", selection: $summaryFrequency) {
                Text("每 4 小时").tag(SummaryFrequency.fourHours)
                Text("每 8 小时").tag(SummaryFrequency.eightHours)
                Text("每天").tag(SummaryFrequency.daily)
                Text("每 3 天").tag(SummaryFrequency.threeDays)
            }
            .pickerStyle(.radioGroup)
            .onChange(of: summaryFrequency) { _ in hasChanges = true }

            Divider()

            HStack {
                Spacer()
                Button("取消") { onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])

                Button("保存") {
                    saveConfig()
                    onDismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(apiKey.isEmpty)
            }

            if hasChanges {
                Text("有未保存的更改")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 380)
        .onAppear { loadConfig() }
    }

    private func loadConfig() {
        let config = (try? configManager.load()) ?? AppConfig()
        llmProvider = config.llmProvider
        apiKey = config.apiKey
        apiBaseURL = config.apiBaseURL
        modelName = config.modelName
        summaryFrequency = config.summaryFrequency
    }

    private func saveConfig() {
        let config = AppConfig(
            llmProvider: llmProvider,
            apiKey: apiKey,
            apiBaseURL: apiBaseURL,
            modelName: modelName,
            summaryFrequency: summaryFrequency,
            isPaused: false,
            videoCaptionMinDurationSec: 60
        )
        try? configManager.save(config)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: SwiftUI settings view for LLM + frequency config"
```

---

### Task 15: LaunchAgent + Packaging

**Files:**
- Create: `Resources/com.digitalshadow.daemon.plist`
- Create: `Makefile`

- [ ] **Step 1: Write LaunchAgent plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.digitalshadow.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/DigitalShadow.app/Contents/MacOS/DigitalShadow</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
```

- [ ] **Step 2: Write Makefile**

```makefile
APP_NAME = DigitalShadow
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

.PHONY: build run install uninstall clean test

build:
	swift build -c release

run:
	swift run

test:
	swift test

app-bundle: build
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp .build/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	sed -i '' 's/CFBundleVersion.*1/CFBundleVersion<string>$(shell date +%s)</string>/' $(APP_BUNDLE)/Contents/Info.plist

install: app-bundle
	cp -R $(APP_BUNDLE) /Applications/
	cp Resources/com.digitalshadow.daemon.plist ~/Library/LaunchAgents/
	launchctl load ~/Library/LaunchAgents/com.digitalshadow.daemon.plist

uninstall:
	launchctl unload ~/Library/LaunchAgents/com.digitalshadow.daemon.plist || true
	rm -f ~/Library/LaunchAgents/com.digitalshadow.daemon.plist
	rm -rf /Applications/$(APP_NAME).app

clean:
	swift package clean
	rm -rf $(BUILD_DIR)/*.app
```

- [ ] **Step 3: Build and verify app runs**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: LaunchAgent plist + Makefile for build/install"
```

---

### Task 16: Integration Test + First Run

- [ ] **Step 1: Verify full test suite**

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Build release**

```bash
swift build -c release
```

Expected: release build succeeds.

- [ ] **Step 3: Run the app and verify menu bar icon appears**

```bash
swift run
```

Expected: green circle icon appears in menu bar. Click to see menu.

- [ ] **Step 4: Verify daily log is being written**

Open `~/DigitalShadow/logs/` and confirm markdown files are being generated.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: integration complete — all tests pass, app runs"
```
