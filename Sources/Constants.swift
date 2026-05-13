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
