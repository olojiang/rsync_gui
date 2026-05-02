import SwiftUI

struct ExecutionPanelView: View {
    let profile: RsyncProfile
    let store: any ProfileStoreProtocol
    let executor: any RsyncExecutorProtocol

    @StateObject private var execVM: ExecutionViewModel
    @State private var showConfirmDelete = false
    @State private var copyFeedback: String?
    @AppStorage("scriptDirectory") private var scriptDirectory = "/Users/hunter/Downloads/Scripts"

    init(profile: RsyncProfile, store: any ProfileStoreProtocol, executor: any RsyncExecutorProtocol) {
        self.profile = profile
        self.store = store
        self.executor = executor
        _execVM = StateObject(wrappedValue: ExecutionViewModel(executor: executor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()

            Divider()

            configDetails
                .padding()

            Divider()

            controlBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            if let feedback = copyFeedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal)
                    .transition(.opacity)
            }

            LogConsoleView(lines: execVM.execution?.outputLines ?? [])
                .padding(.horizontal)
                .padding(.bottom)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.title2)
                    .bold()
                if let status = execVM.execution?.status {
                    HStack(spacing: 8) {
                        StatusBadge(status: status)
                        if let startedAt = execVM.startedAt {
                            ElapsedTimer(startedAt: startedAt, isRunning: execVM.isExecuting)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private var configDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailRow(label: "来源", value: profile.sourcePath)
            DetailRow(label: "目标", value: profile.destinationPath)
            DetailRow(label: "选项", value: profile.options.joined(separator: " ").isEmpty ? "无" : profile.options.joined(separator: " "))
            DetailRow(label: "命令", value: profile.buildCommand().joined(separator: " "))
            ScriptDirectoryRow(scriptDirectory: $scriptDirectory, chooseDirectory: chooseScriptDirectory)
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await execVM.execute(profile: profile) }
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("执行")
                }
            }
            .disabled(execVM.isExecuting)
            .keyboardShortcut("r", modifiers: .command)

            Button {
                Task { await execVM.cancel() }
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("取消")
                }
            }
            .disabled(!execVM.isExecuting)

            Button {
                execVM.clear()
            } label: {
                Text("清空日志")
            }
            .disabled(execVM.execution == nil)

            Divider()
                .frame(height: 20)

            Button {
                copyToPasteboard(profile.buildCommand().joined(separator: " "))
                showFeedback("命令已复制")
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("复制命令")
                }
            }

            Button {
                generateScript()
            } label: {
                HStack {
                    Image(systemName: "doc.badge.arrow.up")
                    Text("生成脚本")
                }
            }

            Button {
                copyToPasteboard(makePathsJSON())
                showFeedback("目录 JSON 已复制")
            } label: {
                HStack {
                    Image(systemName: "curlybraces")
                    Text("复制目录 JSON")
                }
            }

            Spacer()

            if execVM.isExecuting {
                ProgressView()
                    .scaleEffect(0.8)
                Text("执行中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func showFeedback(_ message: String) {
        withAnimation {
            copyFeedback = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copyFeedback = nil
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func makePathsJSON() -> String {
        let dict: [String: String] = [
            "sourcePath": profile.sourcePath,
            "destinationPath": profile.destinationPath
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private func generateScript() {
        let expandedDirectory = (scriptDirectory as NSString).expandingTildeInPath
        let scriptDir = URL(fileURLWithPath: expandedDirectory)
        let scriptName = "sync_\(profile.name.replacingOccurrences(of: " ", with: "_")).sh"
        let scriptURL = scriptDir.appendingPathComponent(scriptName)

        let command = profile.buildCommand().joined(separator: " ")
        let content = """
        #!/bin/bash
        # Generated by RsyncGUI
        # Profile: \(profile.name)
        # Source: \(profile.sourcePath)
        # Destination: \(profile.destinationPath)

        set -e

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting sync: \(profile.name)"
        \(command)
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync finished with exit code $?"
        """

        do {
            try FileManager.default.createDirectory(at: scriptDir, withIntermediateDirectories: true)
            try content.write(to: scriptURL, atomically: true, encoding: .utf8)

            var attributes = [FileAttributeKey: Any]()
            attributes[.posixPermissions] = 0o755
            try FileManager.default.setAttributes(attributes, ofItemAtPath: scriptURL.path)

            showFeedback("脚本已保存: \(scriptName)")
            NSWorkspace.shared.activateFileViewerSelecting([scriptURL])
        } catch {
            showFeedback("保存失败: \(error.localizedDescription)")
        }
    }

    private func chooseScriptDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择脚本保存目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (scriptDirectory as NSString).expandingTildeInPath)

        if panel.runModal() == .OK, let url = panel.url {
            scriptDirectory = url.path
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(label):")
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

private struct ScriptDirectoryRow: View {
    @Binding var scriptDirectory: String
    let chooseDirectory: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("脚本:")
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
            TextField("脚本保存目录", text: $scriptDirectory)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            Button(action: chooseDirectory) {
                Image(systemName: "folder")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)
            .help("选择脚本保存目录")
        }
    }
}

private struct StatusBadge: View {
    let status: TaskStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundColor(color)
        }
    }

    private var color: Color {
        switch status {
        case .pending:    return .secondary
        case .running:    return .blue
        case .success:    return .green
        case .failed:     return .red
        case .cancelled:  return .orange
        }
    }

    private var statusText: String {
        switch status {
        case .pending:    return "等待中"
        case .running:    return "执行中"
        case .success:    return "成功"
        case .failed:     return "失败"
        case .cancelled:  return "已取消"
        }
    }
}

private struct ElapsedTimer: View {
    let startedAt: Date
    let isRunning: Bool
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatElapsed())
            .onReceive(timer) { _ in
                if isRunning {
                    currentTime = Date()
                }
            }
    }

    private func formatElapsed() -> String {
        let elapsed = currentTime.timeIntervalSince(startedAt)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let seconds = Int(elapsed) % 60
        if hours > 0 {
            return String(format: "已运行 %d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "已运行 %02d:%02d", minutes, seconds)
        }
    }
}
