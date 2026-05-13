import Foundation

enum TitleParser {
    private static let patterns: [(NSRegularExpression, String)] = [
        try! (NSRegularExpression(pattern: "^(.*?Pull Request #\\d+).*"), "$1"),
        try! (NSRegularExpression(pattern: "^(.*?) · GitHub$", options: []), "$1 · GitHub"),
        try! (NSRegularExpression(pattern: "^(.*?\\.\\w+)\\s*[—–-]\\s*(.*)$"), "编辑 $1"),
        try! (NSRegularExpression(pattern: "^(.*?)\\s*[—–-]\\s*(zsh|bash|fish|nu)\\b"), "终端：$1"),
        try! (NSRegularExpression(pattern: "^(.*?)\\s*-\\s*YouTube$"), "$1 · YouTube"),
        try! (NSRegularExpression(pattern: "^(.*?)_哔哩哔哩"), "$1 · Bilibili"),
        try! (NSRegularExpression(pattern: "^X / (.*)$"), "浏览 X.com：$1"),
        try! (NSRegularExpression(pattern: "^(.*?) / Twitter$"), "$1 · X.com"),
        try! (NSRegularExpression(pattern: "^Slack — (.*)$"), "Slack：$1"),
        try! (NSRegularExpression(pattern: "^(.*?) — Notion$"), "$1 · Notion"),
    ]

    static func parse(title: String, appName: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return appName }

        for (regex, template) in patterns {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = regex.firstMatch(in: trimmed, range: range) {
                return regex.replacementString(for: match, in: trimmed, offset: 0, template: template)
            }
        }
        return trimmed
    }
}
