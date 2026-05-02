import SwiftUI

@MainActor
struct ContentView: View {
    let store: any ProfileStoreProtocol
    let executor: any RsyncExecutorProtocol

    @StateObject private var listVM: ProfileListViewModel
    @State private var editorWindowController: ProfileEditorWindowController?
    @State private var hostWindow: NSWindow?

    init(store: any ProfileStoreProtocol, executor: any RsyncExecutorProtocol) {
        self.store = store
        self.executor = executor
        _listVM = StateObject(wrappedValue: ProfileListViewModel(store: store))
    }

    var body: some View {
        NavigationSplitView {
            ProfileListView(
                viewModel: listVM,
                openEditor: openEditor
            )
            .frame(minWidth: 200)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if let id = listVM.selectedProfileId,
               let profile = listVM.profiles.first(where: { $0.id == id }) {
                ExecutionPanelView(
                    profile: profile,
                    store: store,
                    executor: executor
                )
            } else {
                EmptyStateView()
            }
        }
        .background(WindowAccessor(window: $hostWindow))
        .onDisappear {
            executor.cancelAllImmediately()
        }
    }

    private func openEditor(profile: RsyncProfile?) {
        AppDiagnostics.log("open editor requested: \(profile?.name ?? "new profile")")
        DispatchQueue.main.async {
            let controller = ProfileEditorWindowController(
                profile: profile,
                store: store,
                parentWindow: hostWindow,
                onSaved: {
                    Task { await listVM.loadProfiles() }
                },
                onClose: {
                    editorWindowController = nil
                }
            )
            editorWindowController = controller
            controller.show()
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            window = view.window
            AppDiagnostics.log("host window captured: \(String(describing: view.window?.frame))")
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            window = nsView.window
        }
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("选择一个配置以查看详情和执行")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("或使用左上角的 + 按钮创建新配置")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
