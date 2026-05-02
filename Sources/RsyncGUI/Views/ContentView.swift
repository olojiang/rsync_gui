import SwiftUI

@MainActor
struct ContentView: View {
    let store: any ProfileStoreProtocol
    let executor: any RsyncExecutorProtocol

    @StateObject private var listVM: ProfileListViewModel
    @State private var editRequest: ProfileEditRequest?

    init(store: any ProfileStoreProtocol, executor: any RsyncExecutorProtocol) {
        self.store = store
        self.executor = executor
        _listVM = StateObject(wrappedValue: ProfileListViewModel(store: store))
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                ProfileListView(
                    viewModel: listVM,
                    editRequest: $editRequest
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

            if let request = editRequest {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .transition(.opacity)

                ProfileEditView(
                    viewModel: ProfileEditViewModel(
                        profile: request.profile,
                        store: store
                    ),
                    onCancel: closeEditor,
                    onSaved: {
                        Task { await listVM.loadProfiles() }
                    }
                )
                .frame(width: 560, height: 340)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .shadow(radius: 24)
                .transition(.scale(scale: 0.98).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.12), value: editRequest?.id)
        .onDisappear {
            executor.cancelAllImmediately()
        }
    }

    private func closeEditor() {
        editRequest = nil
    }
}

struct ProfileEditRequest: Identifiable {
    let id = UUID()
    let profile: RsyncProfile?
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
