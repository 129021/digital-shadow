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
