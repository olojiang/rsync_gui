import SwiftUI
import AppKit

@main
struct RsyncGUIApp: App {
    private let store: any ProfileStoreProtocol
    private let executor: any RsyncExecutorProtocol

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let dir = appSupport.appendingPathComponent("RsyncGUI")
        let fileURL = dir.appendingPathComponent("profiles.json")
        let store = FileProfileStore(fileURL: fileURL)
        let executor = ProcessRsyncExecutor()
        self.store = store
        self.executor = executor

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // 应用退出时终止所有 rsync 子进程
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { _ in
            Task {
                await executor.cancelAll()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, executor: executor)
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentSize)
    }
}
