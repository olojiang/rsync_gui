import SwiftUI

struct ProfileListView: View {
    @StateObject var viewModel: ProfileListViewModel
    let openEditor: (RsyncProfile?) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(viewModel.profiles) { profile in
                    ProfileRow(
                        profile: profile,
                        isSelected: viewModel.selectedProfileId == profile.id,
                        selectAction: {
                            AppDiagnostics.log("profile selected: \(profile.name)")
                            viewModel.selectedProfileId = profile.id
                        },
                        editAction: {
                            openEditor(profile)
                        },
                        deleteAction: {
                            Task { await viewModel.deleteProfile(id: profile.id) }
                        }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
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
    let isSelected: Bool
    let selectAction: () -> Void
    let editAction: () -> Void
    let deleteAction: () -> Void

    @State private var isHoveringEdit = false
    @State private var isHoveringRow = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: selectAction) {
                Text(profile.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: editAction) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isHoveringEdit ? .white : rowForeground)
                    .frame(width: 34, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHoveringEdit ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringEdit = $0 }
            .help("编辑配置")
            .accessibilityLabel("编辑配置")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundColor(rowForeground)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHoveringRow = $0 }
        .contextMenu {
            Button("编辑") {
                editAction()
            }
            Button("删除", role: .destructive) {
                deleteAction()
            }
        }
    }

    private var rowForeground: Color {
        isSelected ? .white : .primary
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor
        }
        if isHoveringRow {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.14)
        }
        return Color.clear
    }
}

private extension ProfileListView {
    var selectedProfile: RsyncProfile? {
        guard let selectedProfileId = viewModel.selectedProfileId else { return nil }
        return viewModel.profiles.first { $0.id == selectedProfileId }
    }
}
