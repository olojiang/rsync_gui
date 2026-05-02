enum TaskStatus: String, Codable, Equatable, Sendable {
    case pending
    case running
    case success
    case failed
    case cancelled
}
