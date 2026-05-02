import Foundation

@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let store: any ProfileStoreProtocol
    let executor: ProcessRsyncExecutor

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let dir = appSupport.appendingPathComponent("RsyncGUI")
        let fileURL = dir.appendingPathComponent("profiles.json")
        store = FileProfileStore(fileURL: fileURL)
        executor = ProcessRsyncExecutor()
    }
}

extension Notification.Name {
    static let profilesDidChange = Notification.Name("RsyncGUI.profilesDidChange")
}
