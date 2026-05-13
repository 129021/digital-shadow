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

        let todayItem = NSMenuItem(title: "今日摘要", action: #selector(openToday), keyEquivalent: "")
        todayItem.target = self
        menu.addItem(todayItem)

        let summarizeItem = NSMenuItem(title: "总结最近 N 小时", action: #selector(summarizeNow), keyEquivalent: "")
        summarizeItem.target = self
        menu.addItem(summarizeItem)

        menu.addItem(.separator())

        pauseMenuItem = NSMenuItem(title: "暂停记录", action: #selector(togglePause), keyEquivalent: "")
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

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
