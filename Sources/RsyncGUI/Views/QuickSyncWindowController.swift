import AppKit
import SwiftUI

@MainActor
final class QuickSyncWindowController: NSObject, NSWindowDelegate {
    private static let contentSize = NSSize(width: 680, height: 520)

    private var panel: NSPanel?
    private let onClose: () -> Void

    init(
        profile: RsyncProfile,
        store: any ProfileStoreProtocol,
        executor: any RsyncExecutorProtocol,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        super.init()

        let rootView = QuickSyncConfirmView(profile: profile, store: store, executor: executor) { [weak self] in
            self?.close()
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "准备开始同步吗？"
        panel.contentViewController = NSHostingController(rootView: rootView)
        panel.setContentSize(Self.contentSize)
        panel.minSize = NSSize(width: 620, height: 460)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.hidesOnDeactivate = false
        panel.center()
        self.panel = panel
    }

    func show() {
        guard let panel else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private struct QuickSyncConfirmView: View {
    let profile: RsyncProfile
    let store: any ProfileStoreProtocol
    let onClose: () -> Void

    @StateObject private var execVM: ExecutionViewModel
    @State private var feedback: String?
    @State private var isSaving = false
    @State private var hasSaved = false

    init(
        profile: RsyncProfile,
        store: any ProfileStoreProtocol,
        executor: any RsyncExecutorProtocol,
        onClose: @escaping () -> Void
    ) {
        self.profile = profile
        self.store = store
        self.onClose = onClose
        _execVM = StateObject(wrappedValue: ExecutionViewModel(executor: executor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                QuickDetailRow(label: "名称", value: profile.name)
                QuickDetailRow(label: "来源", value: profile.sourcePath)
                QuickDetailRow(label: "目标", value: profile.destinationPath)
                QuickDetailRow(label: "选项", value: profile.options.joined(separator: " "))
                QuickDetailRow(label: "命令", value: profile.buildCommand().joined(separator: " "))
            }
            .padding()

            Divider()

            controlBar
                .padding(.horizontal)
                .padding(.vertical, 10)

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundColor(feedback.hasPrefix("失败") ? .red : .green)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }

            LogConsoleView(lines: execVM.execution?.outputLines ?? [])
                .padding(.horizontal)
                .padding(.bottom)
                .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 460)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("准备开始同步吗？")
                    .font(.title2)
                    .bold()
                Text("来自 Finder 右键选择的来源和目标已填好。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let status = execVM.execution?.status {
                QuickStatusBadge(status: status)
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button("取消") {
                onClose()
            }
            .disabled(execVM.isExecuting)

            Button {
                Task { await saveProfile() }
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("保存配置")
                }
            }
            .disabled(isSaving || execVM.isExecuting || hasSaved)

            Button {
                Task {
                    await saveProfile()
                    if hasSaved {
                        await execVM.execute(profile: profile)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("保存并开始")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving || execVM.isExecuting)

            Button {
                Task { await execVM.cancel() }
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("取消执行")
                }
            }
            .disabled(!execVM.isExecuting)

            Spacer()

            if isSaving || execVM.isExecuting {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }

    private func saveProfile() async {
        guard !hasSaved else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await store.save(profile)
            hasSaved = true
            feedback = "配置已保存"
            NotificationCenter.default.post(name: .profilesDidChange, object: nil, userInfo: ["selectedProfileId": profile.id])
        } catch {
            feedback = "失败: \(error.localizedDescription)"
        }
    }
}

private struct QuickDetailRow: View {
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

private struct QuickStatusBadge: View {
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
        case .pending: return .secondary
        case .running: return .blue
        case .success: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    private var statusText: String {
        switch status {
        case .pending: return "等待中"
        case .running: return "执行中"
        case .success: return "成功"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}
