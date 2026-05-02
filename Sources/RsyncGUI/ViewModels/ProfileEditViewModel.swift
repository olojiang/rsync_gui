import Foundation
import Combine

@MainActor
final class ProfileEditViewModel: ObservableObject {
    @Published var profile: RsyncProfile
    @Published var isSaving = false
    @Published var saveSuccess = false
    @Published var errorMessage: String?

    private let store: any ProfileStoreProtocol
    private let logger: AppLogger
    let isNew: Bool

    init(
        profile: RsyncProfile? = nil,
        store: any ProfileStoreProtocol,
        logger: AppLogger = .shared
    ) {
        self.profile = profile ?? RsyncProfile(
            name: "",
            sourcePath: "",
            destinationPath: "",
            options: []
        )
        self.isNew = profile == nil
        self.store = store
        self.logger = logger
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            var toSave = profile
            toSave.updatedAt = Date()
            try await store.save(toSave)
            saveSuccess = true
            await logger.info("Saved profile \(profile.name)", scope: "ProfileEditViewModel")
        } catch {
            errorMessage = error.localizedDescription
            await logger.error("Failed to save profile: \(error)", scope: "ProfileEditViewModel")
        }
    }

    func resetSuccess() {
        saveSuccess = false
    }
}
