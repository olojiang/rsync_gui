import Foundation

enum LogLevel: String, Codable, Equatable, Sendable {
    case debug
    case info
    case warning
    case error
}

struct LogLine: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}
