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
