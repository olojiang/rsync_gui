import SwiftUI

@MainActor
struct ContentView: View {
    let store: any ProfileStoreProtocol
    let executor: any RsyncExecutorProtocol

    @StateObject private var listVM: ProfileListViewModel
    @State private var showEditSheet = false
    @State private var editingProfile: RsyncProfile?

    init(store: any ProfileStoreProtocol, executor: any RsyncExecutorProtocol) {
        self.store = store
        self.executor = executor
        _listVM = StateObject(wrappedValue: ProfileListViewModel(store: store))
    }

    var body: some View {
        NavigationSplitView {
            ProfileListView(
                viewModel: listVM,
                showEditSheet: $showEditSheet,
                editingProfile: $editingProfile
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
        .sheet(isPresented: $showEditSheet, onDismiss: {
            Task { await listVM.loadProfiles() }
        }) {
            ProfileEditView(
                viewModel: ProfileEditViewModel(
                    profile: editingProfile,
                    store: store
                )
            )
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
