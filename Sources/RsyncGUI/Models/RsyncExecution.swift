import Foundation

struct RsyncExecution: Identifiable, Equatable, Sendable {
    let id: UUID
    let profileId: UUID
    let command: String
    var status: TaskStatus
    var outputLines: [LogLine]
    let startedAt: Date
    var finishedAt: Date?
    var logFilePath: String?

    init(
        id: UUID = UUID(),
        profileId: UUID,
        command: String,
        status: TaskStatus = .pending,
        outputLines: [LogLine] = [],
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        logFilePath: String? = nil
    ) {
        self.id = id
        self.profileId = profileId
        self.command = command
        self.status = status
        self.outputLines = outputLines
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.logFilePath = logFilePath
    }
}
