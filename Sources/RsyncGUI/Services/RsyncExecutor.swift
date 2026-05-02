import Foundation

protocol RsyncExecutorProtocol: Sendable {
    func execute(
        profile: RsyncProfile,
        executionId: UUID,
        onOutput: @escaping @Sendable (LogLine) -> Void
    ) async -> RsyncExecution
    func cancel(executionId: UUID) async
    func cancelAll() async
}

actor ProcessRsyncExecutor: RsyncExecutorProtocol {
    private var activeProcesses: [UUID: Process] = [:]

    func execute(
        profile: RsyncProfile,
        executionId: UUID,
        onOutput: @escaping @Sendable (LogLine) -> Void
    ) async -> RsyncExecution {
        guard let rsync = Self.resolveRsync() else {
            let command = profile.buildCommand()
            var failedExecution = RsyncExecution(
                id: executionId,
                profileId: profile.id,
                command: command.joined(separator: " ")
            )
            failedExecution.status = .failed
            failedExecution.finishedAt = Date()
            onOutput(LogLine(level: .error, message: "未在已知路径中找到 rsync"))
            return failedExecution
        }

        let command = Self.command(for: profile, rsync: rsync, onOutput: onOutput)
        let execution = RsyncExecution(
            id: executionId,
            profileId: profile.id,
            command: ([rsync.path] + Array(command.dropFirst())).joined(separator: " ")
        )

        let process = Process()
        let arguments = Array(command.dropFirst())
        process.arguments = arguments
        process.executableURL = URL(fileURLWithPath: rsync.path)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        activeProcesses[execution.id] = process

        onOutput(LogLine(level: .info, message: "rsync 路径: \(rsync.path)"))
        onOutput(LogLine(level: .info, message: "rsync 版本: \(rsync.versionDescription)"))
        onOutput(LogLine(level: .info, message: "开始执行: \(execution.command)"))

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [weak self] in
                var mutableExecution = execution
                mutableExecution.status = .running

                do {
                    try process.run()

                    let group = DispatchGroup()

                    group.enter()
                    DispatchQueue.global().async {
                        Self.readOutput(from: stdoutPipe, level: .info, onOutput: onOutput)
                        group.leave()
                    }

                    group.enter()
                    DispatchQueue.global().async {
                        Self.readOutput(from: stderrPipe, level: .error, onOutput: onOutput)
                        group.leave()
                    }

                    process.waitUntilExit()
                    group.wait()

                    let exitCode = process.terminationStatus
                    mutableExecution.status = exitCode == 0 ? .success : .failed
                    mutableExecution.finishedAt = Date()
                    onOutput(LogLine(
                        level: exitCode == 0 ? .info : .error,
                        message: "执行结束，退出码: \(exitCode)"
                    ))
                } catch {
                    mutableExecution.status = .failed
                    mutableExecution.finishedAt = Date()
                    onOutput(LogLine(level: .error, message: "启动进程失败: \(error.localizedDescription)"))
                }

                Task { [weak self] in
                    await self?.removeProcess(id: execution.id)
                }

                continuation.resume(returning: mutableExecution)
            }
        }
    }

    private static func resolveRsync() -> ResolvedRsync? {
        let possiblePaths = ["/opt/homebrew/bin/rsync", "/usr/local/bin/rsync", "/usr/bin/rsync"]
        let existing = possiblePaths.filter { FileManager.default.isExecutableFile(atPath: $0) }
        let resolved = existing.map { ResolvedRsync(path: $0, versionDescription: versionDescription(at: $0)) }
        return resolved.first { $0.supportsInfoProgress } ?? resolved.first
    }

    private static func command(
        for profile: RsyncProfile,
        rsync: ResolvedRsync,
        onOutput: @escaping @Sendable (LogLine) -> Void
    ) -> [String] {
        var command = profile.buildCommand()
        guard !rsync.supportsInfoProgress else { return command }

        var didReplaceInfoProgress = false
        command = command.map { option in
            if option == "--info=progress2" {
                didReplaceInfoProgress = true
                return "--progress"
            }
            return option
        }

        if didReplaceInfoProgress {
            onOutput(LogLine(
                level: .warning,
                message: "\(rsync.path) 不支持 --info=progress2，已自动降级为 --progress"
            ))
        }

        return command
    }

    private static func versionDescription(at path: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.split(separator: "\n").first.map(String.init) ?? "unknown"
        } catch {
            return "unknown (\(error.localizedDescription))"
        }
    }

    /// 从 Pipe 中读取数据，识别换行和 rsync 进度常用的回车刷新。
    private static func readOutput(
        from pipe: Pipe,
        level: LogLevel,
        onOutput: @escaping @Sendable (LogLine) -> Void
    ) {
        var parser = RsyncOutputParser()
        let handle = pipe.fileHandleForReading

        do {
            while true {
                guard let data = try handle.read(upToCount: 4096) else { break }
                guard !data.isEmpty else { break }

                for line in parser.append(data) {
                    onOutput(LogLine(level: level, message: line))
                }
            }
        } catch {
            onOutput(LogLine(level: .error, message: "读取 \(level) 管道时出错: \(error.localizedDescription)"))
        }

        for line in parser.flush() {
            onOutput(LogLine(level: level, message: line))
        }
    }

    private func removeProcess(id: UUID) {
        activeProcesses.removeValue(forKey: id)
    }

    func cancel(executionId: UUID) {
        guard let process = activeProcesses[executionId] else { return }
        process.terminate()
    }

    func cancelAll() {
        for (_, process) in activeProcesses {
            process.terminate()
        }
        activeProcesses.removeAll()
    }
}

private struct ResolvedRsync {
    let path: String
    let versionDescription: String

    var supportsInfoProgress: Bool {
        guard versionDescription.contains("version 3.") || versionDescription.contains("version 4.") else {
            return false
        }
        return !versionDescription.localizedCaseInsensitiveContains("openrsync")
    }
}

struct RsyncOutputParser {
    private var buffer = Data()

    mutating func append(_ data: Data) -> [String] {
        buffer.append(data)
        return drainCompleteLines()
    }

    mutating func flush() -> [String] {
        guard !buffer.isEmpty else { return [] }
        let line = decode(buffer)
        buffer.removeAll(keepingCapacity: true)
        return line.map { [$0] } ?? []
    }

    private mutating func drainCompleteLines() -> [String] {
        var lines: [String] = []

        while let separatorIndex = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer.prefix(upTo: separatorIndex)
            var nextIndex = buffer.index(after: separatorIndex)

            // Treat CRLF as one separator.
            if buffer[separatorIndex] == 0x0D,
               nextIndex < buffer.endIndex,
               buffer[nextIndex] == 0x0A {
                nextIndex = buffer.index(after: nextIndex)
            }

            buffer = Data(buffer.suffix(from: nextIndex))

            if let line = decode(lineData) {
                lines.append(line)
            }
        }

        return lines
    }

    private func decode(_ data: Data) -> String? {
        guard !data.isEmpty,
              let line = String(data: data, encoding: .utf8) else {
            return nil
        }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
