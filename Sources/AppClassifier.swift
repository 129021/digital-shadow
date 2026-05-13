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
