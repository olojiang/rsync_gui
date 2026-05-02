import SwiftUI

struct ProfileListView: View {
    @StateObject var viewModel: ProfileListViewModel
    let openEditor: (RsyncProfile?) -> Void

    var body: some View {
        List(viewModel.profiles, selection: $viewModel.selectedProfileId) { profile in
            ProfileRow(
                profile: profile,
                editAction: {
                    openEditor(profile)
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
            ToolbarItemGroup {
                Button {
                    if let selectedProfile {
                        openEditor(selectedProfile)
                    }
                } label: {
                    Image(systemName: "pencil")
                }
                .disabled(selectedProfile == nil)
                .help("编辑选中的配置")

                Button {
                    openEditor(nil)
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
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHoveringEdit ? .white : .primary)
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHoveringEdit ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
                .onHover { isHoveringEdit = $0 }
                .onTapGesture(perform: editAction)
                .help("编辑配置")
                .accessibilityLabel("编辑配置")
                .accessibilityAddTraits(.isButton)
        }
        .padding(.vertical, 2)
    }
}

private extension ProfileListView {
    var selectedProfile: RsyncProfile? {
        guard let selectedProfileId = viewModel.selectedProfileId else { return nil }
        return viewModel.profiles.first { $0.id == selectedProfileId }
    }
}
