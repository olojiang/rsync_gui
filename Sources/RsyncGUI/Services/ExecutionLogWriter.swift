import AppKit
import Foundation

actor ExecutionLogWriter {
    let fileURL: URL

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let lineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    init(profile: RsyncProfile, executionId: UUID, command: String) throws {
        let logsDir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/RsyncGUI", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let timestamp = Self.filenameFormatter.string(from: Date())
        let safeName = Self.safeFilename(profile.name)
        fileURL = logsDir.appendingPathComponent("\(timestamp)-\(safeName)-\(executionId.uuidString.prefix(8)).log")

        let header = """
        RsyncGUI execution log
        Profile: \(profile.name)
        Source: \(profile.sourcePath)
        Destination: \(profile.destinationPath)
        Command: \(command)
        Started: \(Self.lineFormatter.string(from: Date()))

        """
        try header.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func write(_ line: LogLine) {
        append("[\(Self.lineFormatter.string(from: line.timestamp))] [\(line.level.rawValue.uppercased())] \(line.message)\n")
    }

    func writeMessage(_ message: String) {
        append("[\(Self.lineFormatter.string(from: Date()))] [INFO] \(message)\n")
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            NSLog("RsyncGUI failed to append execution log: \(error.localizedDescription)")
        }
    }

    private static func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let filename = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return filename.isEmpty ? "rsync" : filename
    }
}
