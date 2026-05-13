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
                currentSession = ActivitySession(
                    id: session.id,
                    startTime: session.startTime,
                    endTime: event.timestamp,
                    appGroup: unionAppGroup(session.appGroup, event.appName),
                    title: session.title,
                    category: session.category
                )
            } else {
                finalizeCurrent()
                startNewSession(event)
            }
        } else {
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
        let topTitle = windowTitleAppearances.max(by: { $0.value < $1.value })?.key ?? ""
        let topApp = appGroupAppearances.max(by: { $0.value < $1.value })?.key ?? ""
        if sessionEvents.first(where: { $0.windowTitle == topTitle }) != nil {
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
