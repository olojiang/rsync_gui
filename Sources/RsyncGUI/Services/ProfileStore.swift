import Foundation

protocol ProfileStoreProtocol: Sendable {
    func loadAll() async throws -> [RsyncProfile]
    func save(_ profile: RsyncProfile) async throws
    func delete(id: UUID) async throws
}

actor FileProfileStore: ProfileStoreProtocol {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func loadAll() throws -> [RsyncProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([RsyncProfile].self, from: data)
    }

    func save(_ profile: RsyncProfile) throws {
        var profiles = try loadAll()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(profiles)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }

    func delete(id: UUID) throws {
        var profiles = try loadAll()
        profiles.removeAll(where: { $0.id == id })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(profiles)
        try data.write(to: fileURL)
    }
}
