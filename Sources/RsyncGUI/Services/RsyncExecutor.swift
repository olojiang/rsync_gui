import Darwin
import Foundation

protocol RsyncExecutorProtocol: Sendable {
    func execute(
        profile: RsyncProfile,
        executionId: UUID,
        onOutput: @escaping @Sendable (LogLine) -> Void
    ) async -> RsyncExecution
    func cancel(executionId: UUID) async
    func cancelAll() async
    func cancelAllImmediately()
}

final class ProcessRsyncExecutor: RsyncExecutorProtocol, @unchecked Sendable {
    private var activeProcesses: [UUID: Process] = [:]
    private var cancelledExecutionIds: Set<UUID> = []
    private let processLock = NSLock()
    private let executionQueue: RsyncExecutionQueue

    init(maxConcurrentExecutions: Int = 1) {
        executionQueue = RsyncExecutionQueue(maxConcurrentExecutions: maxConcurrentExecutions)
    }

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

        if let validationError = Self.validatePaths(profile: profile) {
            var failedExecution = execution
            failedExecution.status = .failed
            failedExecution.finishedAt = Date()
            onOutput(LogLine(level: .error, message: validationError))
            onOutput(LogLine(level: .error, message: "未启动 rsync：请先修正目录配置"))
            return failedExecution
        }

        onOutput(LogLine(level: .info, message: "已加入执行队列，等待其他 rsync 完成"))
        guard await executionQueue.waitForTurn(executionId: execution.id) else {
            var cancelledExecution = execution
            cancelledExecution.status = .cancelled
            cancelledExecution.finishedAt = Date()
            onOutput(LogLine(level: .warning, message: "排队任务已取消，未启动 rsync"))
            cleanupCancelledState(id: execution.id)
            return cancelledExecution
        }

        let result = await runProcess(
            execution: execution,
            command: command,
            rsync: rsync,
            onOutput: onOutput
        )
        await executionQueue.finish(executionId: execution.id)
        return result
    }

    private func runProcess(
        execution: RsyncExecution,
        command: [String],
        rsync: ResolvedRsync,
        onOutput: @escaping @Sendable (LogLine) -> Void
    ) async -> RsyncExecution {
        let process = Process()
        let arguments = Array(command.dropFirst())
        process.arguments = arguments
        process.executableURL = URL(fileURLWithPath: rsync.path)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        guard insertProcessIfNotCancelled(process, id: execution.id) else {
            var cancelledExecution = execution
            cancelledExecution.status = .cancelled
            cancelledExecution.finishedAt = Date()
            onOutput(LogLine(level: .warning, message: "排队任务已取消，未启动 rsync"))
            cleanupCancelledState(id: execution.id)
            return cancelledExecution
        }

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
                    let wasCancelled = self?.wasCancelled(executionId: execution.id) ?? false
                    mutableExecution.status = wasCancelled ? .cancelled : (exitCode == 0 ? .success : .failed)
                    mutableExecution.finishedAt = Date()
                    onOutput(LogLine(
                        level: mutableExecution.status == .success ? .info : .error,
                        message: "执行结束，退出码: \(exitCode)"
                    ))
                } catch {
                    let wasCancelled = self?.wasCancelled(executionId: execution.id) ?? false
                    mutableExecution.status = wasCancelled ? .cancelled : .failed
                    mutableExecution.finishedAt = Date()
                    onOutput(LogLine(level: .error, message: "启动进程失败: \(error.localizedDescription)"))
                }

                self?.removeProcessAndCancelledState(id: execution.id)

                continuation.resume(returning: mutableExecution)
            }
        }
    }

    private static func validatePaths(profile: RsyncProfile) -> String? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: profile.sourcePath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "来源目录不存在或不是目录: \(profile.sourcePath)"
        }

        isDirectory = false
        guard fileManager.fileExists(atPath: profile.destinationPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "目标目录不存在或不是目录: \(profile.destinationPath)"
        }

        return nil
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

    private func insertProcessIfNotCancelled(_ process: Process, id: UUID) -> Bool {
        processLock.lock()
        if cancelledExecutionIds.contains(id) {
            processLock.unlock()
            return false
        }
        activeProcesses[id] = process
        processLock.unlock()
        return true
    }

    private func removeProcessAndCancelledState(id: UUID) {
        processLock.lock()
        activeProcesses.removeValue(forKey: id)
        cancelledExecutionIds.remove(id)
        processLock.unlock()
    }

    private func cleanupCancelledState(id: UUID) {
        processLock.lock()
        cancelledExecutionIds.remove(id)
        processLock.unlock()
    }

    private func wasCancelled(executionId: UUID) -> Bool {
        processLock.lock()
        let wasCancelled = cancelledExecutionIds.contains(executionId)
        processLock.unlock()
        return wasCancelled
    }

    private func markCancelledAndProcess(executionId: UUID) -> Process? {
        processLock.lock()
        cancelledExecutionIds.insert(executionId)
        let process = activeProcesses[executionId]
        processLock.unlock()
        return process
    }

    func cancel(executionId: UUID) async {
        await executionQueue.cancel(executionId: executionId)

        let process = markCancelledAndProcess(executionId: executionId)

        guard let process else { return }
        process.terminate()
    }

    func cancelAll() async {
        await executionQueue.cancelAll()
        terminateAllImmediately()
    }

    func cancelAllImmediately() {
        Task { await executionQueue.cancelAll() }
        terminateAllImmediately()
    }

    private func terminateAllImmediately() {
        processLock.lock()
        let activeIds = Array(activeProcesses.keys)
        let processes = Array(activeProcesses.values)
        cancelledExecutionIds.formUnion(activeIds)
        activeProcesses.removeAll()
        processLock.unlock()

        for process in processes where process.isRunning {
            process.terminate()
        }

        let deadline = Date().addingTimeInterval(2)
        while processes.contains(where: { $0.isRunning }) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        for process in processes where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

actor RsyncExecutionQueue {
    private struct Waiter {
        let executionId: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let maxConcurrentExecutions: Int
    private var runningCount = 0
    private var waiters: [Waiter] = []

    init(maxConcurrentExecutions: Int) {
        self.maxConcurrentExecutions = max(1, maxConcurrentExecutions)
    }

    func waitForTurn(executionId: UUID) async -> Bool {
        if runningCount < maxConcurrentExecutions {
            runningCount += 1
            return true
        }

        return await withCheckedContinuation { continuation in
            waiters.append(Waiter(executionId: executionId, continuation: continuation))
        }
    }

    func finish(executionId: UUID) {
        guard runningCount > 0 else { return }
        runningCount -= 1
        startNextIfPossible()
    }

    func cancel(executionId: UUID) {
        guard let index = waiters.firstIndex(where: { $0.executionId == executionId }) else {
            return
        }

        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    func cancelAll() {
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.continuation.resume(returning: false)
        }
    }

    private func startNextIfPossible() {
        guard runningCount < maxConcurrentExecutions, !waiters.isEmpty else { return }
        let waiter = waiters.removeFirst()
        runningCount += 1
        waiter.continuation.resume(returning: true)
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
