import SwiftUI
import AppKit

@main
struct RsyncGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let store: any ProfileStoreProtocol
    private let executor: ProcessRsyncExecutor

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

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { _ in
            executor.cancelAllImmediately()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, executor: executor)
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 960, height: 640)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
