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
