import SwiftUI
import AppKit

@main
struct RsyncGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let store: any ProfileStoreProtocol
    private let executor: ProcessRsyncExecutor

    init() {
        let container = AppContainer.shared
        store = container.store
        executor = container.executor
        let appExecutor = container.executor

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { _ in
            appExecutor.cancelAllImmediately()
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var finderSyncServiceProvider: FinderSyncServiceProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider = FinderSyncServiceProvider(
            store: AppContainer.shared.store,
            executor: AppContainer.shared.executor
        )
        finderSyncServiceProvider = provider
        NSApplication.shared.servicesProvider = provider
        NSUpdateDynamicServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
