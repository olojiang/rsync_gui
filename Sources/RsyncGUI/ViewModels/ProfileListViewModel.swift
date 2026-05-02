import Foundation
import Combine

@MainActor
final class ProfileListViewModel: ObservableObject {
    @Published var profiles: [RsyncProfile] = []
    @Published var selectedProfileId: UUID?
    @Published var errorMessage: String?

    private let store: any ProfileStoreProtocol
    private let logger: AppLogger

    init(store: any ProfileStoreProtocol, logger: AppLogger = .shared) {
        self.store = store
        self.logger = logger
    }

    func loadProfiles() async {
        do {
            profiles = try await store.loadAll()
            await logger.info("Loaded \(profiles.count) profiles", scope: "ProfileListViewModel")
        } catch {
            errorMessage = error.localizedDescription
            await logger.error("Failed to load profiles: \(error)", scope: "ProfileListViewModel")
        }
    }

    func deleteProfile(id: UUID) async {
        do {
            try await store.delete(id: id)
            profiles.removeAll(where: { $0.id == id })
            if selectedProfileId == id {
                selectedProfileId = nil
            }
            await logger.info("Deleted profile \(id)", scope: "ProfileListViewModel")
        } catch {
            errorMessage = error.localizedDescription
            await logger.error("Failed to delete profile: \(error)", scope: "ProfileListViewModel")
        }
    }

    func selectProfile(id: UUID?) {
        selectedProfileId = id
    }
}
