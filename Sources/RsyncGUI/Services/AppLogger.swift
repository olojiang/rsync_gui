import Foundation

actor AppLogger {
    static let shared = AppLogger()

    private var buffer: [LogLine] = []
    private var continuations: [UUID: AsyncStream<LogLine>.Continuation] = [:]
    private let maxBufferSize = 1000

    private func log(level: LogLevel, message: String, scope: String) {
        let line = LogLine(
            level: level,
            message: scope.isEmpty ? message : "[\(scope)] \(message)"
        )
        buffer.append(line)
        if buffer.count > maxBufferSize {
            buffer.removeFirst(buffer.count - maxBufferSize)
        }
        for cont in continuations.values {
            cont.yield(line)
        }
    }

    func debug(_ message: String, scope: String = "") {
        log(level: .debug, message: message, scope: scope)
    }

    func info(_ message: String, scope: String = "") {
        log(level: .info, message: message, scope: scope)
    }

    func warning(_ message: String, scope: String = "") {
        log(level: .warning, message: message, scope: scope)
    }

    func error(_ message: String, scope: String = "") {
        log(level: .error, message: message, scope: scope)
    }

    func recentLogs(limit: Int = 100) -> [LogLine] {
        Array(buffer.suffix(limit))
    }

    func observe() -> AsyncStream<LogLine> {
        AsyncStream { continuation in
            let id = UUID()
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
