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
        // Create data directories
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        summaryScheduler.stop()
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

        // Write daily log incrementally
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

    func appMonitorDidDetectIdle(_ monitor: AppMonitor, since: Date) {}
    func appMonitorDidBecomeActive(_ monitor: AppMonitor) {}
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
                for (i, sr) in result.sessions.enumerated() where i < sessions.count {
                    var updated = sessions[i]
                    updated.title = sr.title
                    updated.summary = sr.summary
                    updated.category = sr.category
                    try? eventStore.insertSession(updated)
                }
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
