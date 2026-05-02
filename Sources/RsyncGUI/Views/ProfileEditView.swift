import SwiftUI

struct RsyncOptionPreset: Identifiable {
    let id: String
    let group: String
    let name: String
    let options: [String]

    init(group: String, name: String, options: [String]) {
        self.group = group
        self.name = name
        self.options = options
        id = "\(group)/\(name)"
    }
}

extension RsyncOptionPreset {
    static let custom = RsyncOptionPreset(group: "自定义", name: "自定义", options: [])

    static let allPresets: [RsyncOptionPreset] = [
        custom,

        RsyncOptionPreset(group: "本地同步", name: "增量更新（脚本同款）", options: ["-a", "--human-readable", "--info=progress2"]),
        RsyncOptionPreset(group: "本地同步", name: "增量更新（显示文件进度）", options: ["-a", "--human-readable", "--progress"]),
        RsyncOptionPreset(group: "本地同步", name: "归档同步（安静）", options: ["-a", "--human-readable"]),
        RsyncOptionPreset(group: "本地同步", name: "压缩同步（慢盘/网络盘）", options: ["-az", "--human-readable", "--info=progress2"]),

        RsyncOptionPreset(group: "镜像删除", name: "本地镜像（删除目标多余）", options: ["-a", "--delete", "--human-readable", "--info=progress2"]),
        RsyncOptionPreset(group: "镜像删除", name: "本地镜像（延迟删除）", options: ["-a", "--delete-delay", "--human-readable", "--info=progress2"]),
        RsyncOptionPreset(group: "镜像删除", name: "严格镜像（校验和一致）", options: ["-a", "--delete", "--checksum", "--human-readable", "--info=progress2"]),

        RsyncOptionPreset(group: "备份保留", name: "增量备份（保留旧文件）", options: ["-a", "--backup", "--human-readable", "--info=progress2"]),
        RsyncOptionPreset(group: "备份保留", name: "备份到 .rsync-backup", options: ["-a", "--backup", "--backup-dir=.rsync-backup", "--human-readable", "--info=progress2"]),
        RsyncOptionPreset(group: "备份保留", name: "只补新文件（不覆盖）", options: ["-a", "--ignore-existing", "--human-readable", "--info=progress2"]),
        RsyncOptionPreset(group: "备份保留", name: "只更新较新的文件", options: ["-a", "--update", "--human-readable", "--info=progress2"]),

        RsyncOptionPreset(group: "测试检查", name: "模拟运行（镜像预演）", options: ["-a", "--delete", "--dry-run", "--itemize-changes", "--human-readable", "--info=progress2"]),
        RsyncOptionPreset(group: "测试检查", name: "差异检查（校验和）", options: ["-a", "--dry-run", "--checksum", "--itemize-changes", "--human-readable"]),
        RsyncOptionPreset(group: "测试检查", name: "仅列出变化", options: ["-a", "--dry-run", "--itemize-changes", "--human-readable"]),

        RsyncOptionPreset(group: "远程 SSH", name: "远程增量同步", options: ["-az", "-e", "ssh", "--human-readable", "--info=progress2"]),
        RsyncOptionPreset(group: "远程 SSH", name: "远程镜像同步", options: ["-az", "--delete", "-e", "ssh", "--human-readable", "--info=progress2"]),
        RsyncOptionPreset(group: "远程 SSH", name: "远程断点续传", options: ["-az", "--partial", "-e", "ssh", "--human-readable", "--info=progress2"]),

        RsyncOptionPreset(group: "大文件/恢复", name: "断点续传（安全校验）", options: ["-a", "--partial", "--append-verify", "--human-readable", "--info=progress2"]),
        RsyncOptionPreset(group: "大文件/恢复", name: "保留部分文件", options: ["-a", "--partial", "--human-readable", "--info=progress2"]),
        RsyncOptionPreset(group: "大文件/恢复", name: "稀疏文件优化", options: ["-a", "--sparse", "--human-readable", "--info=progress2"]),
    ]

    static let groupedPresets: [(name: String, presets: [RsyncOptionPreset])] = {
        let groupOrder = ["自定义", "本地同步", "镜像删除", "备份保留", "测试检查", "远程 SSH", "大文件/恢复"]
        return groupOrder.compactMap { group in
            let presets = allPresets.filter { $0.group == group }
            return presets.isEmpty ? nil : (group, presets)
        }
    }()
}

struct ProfileEditView: View {
    @StateObject var viewModel: ProfileEditViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPresetId: String = RsyncOptionPreset.custom.id

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.isNew ? "新建配置" : "编辑配置")
                .font(.title2)
                .bold()

            Group {
                TextField("配置名称", text: $viewModel.profile.name)
                    .textFieldStyle(.roundedBorder)

                PathPicker(path: $viewModel.profile.sourcePath, label: "来源:")
                PathPicker(path: $viewModel.profile.destinationPath, label: "目标:")

                HStack(spacing: 8) {
                    Text("预设:")
                        .frame(width: 60, alignment: .trailing)
                    Picker("", selection: $selectedPresetId) {
                        ForEach(RsyncOptionPreset.groupedPresets, id: \.name) { group in
                            Section(group.name) {
                                ForEach(group.presets) { preset in
                                    Text(preset.name).tag(preset.id)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedPresetId) { newId in
                        if let preset = RsyncOptionPreset.allPresets.first(where: { $0.id == newId }) {
                            viewModel.profile.options = preset.options
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text("选项:")
                        .frame(width: 60, alignment: .trailing)
                    TextField("rsync 选项，空格分隔", text: optionsBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                if viewModel.isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Button("取消") {
                    dismiss()
                }
                Button("保存") {
                    Task {
                        await viewModel.save()
                        if viewModel.saveSuccess {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.profile.name.isEmpty || viewModel.profile.sourcePath.isEmpty || viewModel.profile.destinationPath.isEmpty)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 540, idealWidth: 560, minHeight: 320, idealHeight: 340)
    }

    private var optionsBinding: Binding<String> {
        Binding {
            viewModel.profile.options.joined(separator: " ")
        } set: { newValue in
            viewModel.profile.options = newValue.split(separator: " ").map(String.init)
            selectedPresetId = RsyncOptionPreset.custom.id
        }
    }
}
