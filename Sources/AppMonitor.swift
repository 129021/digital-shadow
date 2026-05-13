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
    private var lastFocusedApp: NSRunningApplication?
    private var lastWindowTitle: String?

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appDidActivate(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)

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
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        lastFocusedApp = app
        lastActiveTime = Date()
        queue.async { [weak self] in self?.recordCurrent() }
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
        guard let app = lastFocusedApp,
              let bundleId = app.bundleIdentifier,
              classifier.isBrowser(bundleId: bundleId) else { return nil }

        let script: String
        if bundleId == "com.apple.Safari" {
            script = "tell application \"Safari\" to return URL of front document"
        } else {
            script = "tell application \"\(app.localizedName ?? "")\" to return URL of active tab of front window"
        }

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        let result = appleScript?.executeAndReturnError(&error)
        return result?.stringValue
    }
}
