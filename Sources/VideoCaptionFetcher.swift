import Foundation

final class VideoCaptionFetcher {
    private let videoDomains = Constants.videoDomains

    func isVideoURL(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        return videoDomains.contains(where: { host.contains($0) })
    }

    func extractYTVideoID(_ url: String) -> String? {
        guard let components = URLComponents(string: url) else { return nil }
        if let host = components.host, host.contains("youtu.be") {
            return components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return components.queryItems?.first(where: { $0.name == "v" })?.value
    }

    func buildCommand(url: String, outputPath: String) -> String {
        "yt-dlp --write-auto-subs --sub-format srt1 --skip-download --sub-langs en,zh-Hans --max-subs 1 -o \"\(outputPath)\" \"\(url)\""
    }

    func fetchCaptions(for url: String) async throws -> String? {
        guard isVideoURL(url) else { return nil }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("digitalshadow_captions_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let outputTemplate = tmpDir.appendingPathComponent("%(id)s").path
        let cmd = buildCommand(url: url, outputPath: outputTemplate)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "\(cmd) 2>/dev/null"]
        process.currentDirectoryURL = tmpDir

        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()

        let files = (try? FileManager.default.contentsOfDirectory(at: tmpDir,
            includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "srt" || file.pathExtension == "vtt" {
            let content = try String(contentsOf: file, encoding: .utf8)
            let text = parseSubtitleText(content)
            return String(text.prefix(500))
        }
        return nil
    }

    private func parseSubtitleText(_ raw: String) -> String {
        var lines: [String] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.contains("-->") { continue }
            if let _ = Int(trimmed) { continue }
            if trimmed.hasPrefix("WEBVTT") { continue }
            lines.append(trimmed)
        }
        return lines.joined(separator: " ")
    }
}
