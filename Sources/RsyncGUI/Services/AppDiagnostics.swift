import Foundation

enum AppDiagnostics {
    private static let lineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static var logFileURL: URL {
        let logsDir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/RsyncGUI", isDirectory: true)
        return logsDir.appendingPathComponent("app.log")
    }

    static func log(_ message: String) {
        NSLog("[RsyncGUI] \(message)")

        let line = "[\(lineFormatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            let fileURL = logFileURL
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try Data().write(to: fileURL)
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            NSLog("[RsyncGUI] failed to write app diagnostics: \(error.localizedDescription)")
        }
    }
}
