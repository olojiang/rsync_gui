import Foundation

struct RsyncProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var sourcePath: String
    var destinationPath: String
    var options: [String]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        sourcePath: String,
        destinationPath: String,
        options: [String],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.options = options
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func buildCommand() -> [String] {
        var command = ["rsync"]
        command.append(contentsOf: options)
        command.append(sourcePath)
        command.append(destinationPath)
        return command
    }
}
