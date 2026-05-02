import SwiftUI

struct ProfileListView: View {
    @StateObject var viewModel: ProfileListViewModel
    @Binding var showEditSheet: Bool
    @Binding var editingProfile: RsyncProfile?

    var body: some View {
        List(viewModel.profiles, selection: $viewModel.selectedProfileId) { profile in
            ProfileRow(
                profile: profile,
                editAction: {
                    editingProfile = profile
                    showEditSheet = true
                }
            )
            .tag(profile.id)
        }
        .contextMenu(forSelectionType: UUID.self) { selection in
            Button("删除") {
                for id in selection {
                    Task { await viewModel.deleteProfile(id: id) }
                }
            }
        } primaryAction: { selection in
            // no primary action
        }
        .toolbar {
            ToolbarItem {
                Button {
                    editingProfile = nil
                    showEditSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("新建配置")
            }
        }
        .task {
            await viewModel.loadProfiles()
        }
        .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("确定") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

private struct ProfileRow: View {
    let profile: RsyncProfile
    let editAction: () -> Void

    @State private var isHoveringEdit = false

    var body: some View {
        HStack {
            Text(profile.name)
                .lineLimit(1)
            Spacer()
            Button(action: editAction) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isHoveringEdit ? .white : .primary)
                    .frame(width: 32, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHoveringEdit ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .opacity(isHoveringEdit ? 1 : 0.85)
            .onHover { isHoveringEdit = $0 }
            .help("编辑配置")
        }
        .padding(.vertical, 2)
    }
}
