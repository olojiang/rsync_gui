import Foundation
import Combine

@MainActor
final class ExecutionViewModel: ObservableObject {
    @Published var execution: RsyncExecution?
    @Published var isExecuting = false
    @Published var errorMessage: String?
    @Published var startedAt: Date?

    private let executor: any RsyncExecutorProtocol
    private let logger: AppLogger

    init(
        executor: any RsyncExecutorProtocol,
        logger: AppLogger = .shared
    ) {
        self.executor = executor
        self.logger = logger
    }

    func execute(profile: RsyncProfile) async {
        isExecuting = true
        errorMessage = nil
        startedAt = Date()
        defer { isExecuting = false }

        await logger.info(
            "Starting execution for profile \(profile.name)",
            scope: "ExecutionViewModel"
        )

        // 先初始化 execution，让 onOutput 回调可以实时追加日志
        let initialExecution = RsyncExecution(
            profileId: profile.id,
            command: profile.buildCommand().joined(separator: " "),
            status: .running
        )
        let logWriter: ExecutionLogWriter?
        do {
            logWriter = try ExecutionLogWriter(
                profile: profile,
                executionId: initialExecution.id,
                command: initialExecution.command
            )
        } catch {
            logWriter = nil
            errorMessage = "创建执行日志失败: \(error.localizedDescription)"
        }

        var executionWithLog = initialExecution
        executionWithLog.logFilePath = logWriter?.fileURL.path
        self.execution = executionWithLog

        if let logPath = logWriter?.fileURL.path {
            let line = LogLine(level: .info, message: "执行日志: \(logPath)")
            await logWriter?.write(line)
            if var exec = self.execution {
                exec.outputLines.append(line)
                self.execution = exec
            }
        }

        let result = await executor.execute(profile: profile, executionId: initialExecution.id) { [weak self] line in
            Task {
                await logWriter?.write(line)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if var exec = self.execution {
                    exec.outputLines.append(line)
                    self.execution = exec
                }
            }
        }

        // 如果用户已取消，不要覆盖状态
        if self.execution?.status != .cancelled {
            if var exec = self.execution {
                exec.status = result.status
                exec.finishedAt = result.finishedAt
                exec.logFilePath = logWriter?.fileURL.path
                self.execution = exec
            }
        }

        await logWriter?.writeMessage("Finished with status \(result.status.rawValue)")

        await logger.info(
            "Execution finished with status \(result.status)",
            scope: "ExecutionViewModel"
        )
    }

    func cancel() async {
        guard let id = execution?.id else {
            await logger.warning("Cancel called but no active execution", scope: "ExecutionViewModel")
            return
        }

        await executor.cancel(executionId: id)

        // 立即更新 UI 状态，不等待 executor 完成
        if var exec = execution {
            exec.status = .cancelled
            exec.finishedAt = Date()
            execution = exec
        }
        isExecuting = false

        await logger.info("Cancelled execution \(id)", scope: "ExecutionViewModel")
    }

    func clear() {
        execution = nil
        errorMessage = nil
        startedAt = nil
    }
}
