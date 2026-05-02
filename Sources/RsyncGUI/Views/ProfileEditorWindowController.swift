import AppKit
import SwiftUI

@MainActor
final class ProfileEditorWindowController: NSObject, NSWindowDelegate {
    private static let contentSize = NSSize(width: 560, height: 340)

    private var panel: NSPanel?
    private let onClose: () -> Void

    init(
        profile: RsyncProfile?,
        store: any ProfileStoreProtocol,
        parentWindow: NSWindow?,
        onSaved: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        super.init()

        let title = profile == nil ? "新建配置" : "编辑配置"
        let rootView = ProfileEditView(
            viewModel: ProfileEditViewModel(profile: profile, store: store),
            onCancel: { [weak self] in
                AppDiagnostics.log("profile editor cancel requested")
                self?.close()
            },
            onSaved: { [weak self] in
                AppDiagnostics.log("profile editor save completed")
                onSaved()
                self?.close()
            }
        )
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.contentViewController = NSHostingController(rootView: rootView)
        panel.setContentSize(Self.contentSize)
        panel.minSize = NSSize(width: Self.contentSize.width, height: Self.contentSize.height + 28)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.hidesOnDeactivate = false
        panel.level = .floating
        position(panel, relativeTo: parentWindow)
        self.panel = panel
    }

    func show() {
        guard let panel else { return }
        AppDiagnostics.log("profile editor show: \(panel.title)")
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        AppDiagnostics.log("profile editor closed")
        onClose()
    }

    private func position(_ panel: NSPanel, relativeTo parentWindow: NSWindow?) {
        let panelSize = panel.frame.size.width > 0 && panel.frame.size.height > 40
            ? panel.frame.size
            : NSSize(width: Self.contentSize.width, height: Self.contentSize.height + 28)
        let referenceFrame = parentWindow?.frame ?? NSScreen.main?.visibleFrame ?? panel.frame
        let screenFrame = parentWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? referenceFrame

        var origin = NSPoint(
            x: referenceFrame.midX - panelSize.width / 2,
            y: referenceFrame.midY - panelSize.height / 2
        )

        origin.x = min(max(origin.x, screenFrame.minX + 12), screenFrame.maxX - panelSize.width - 12)
        origin.y = min(max(origin.y, screenFrame.minY + 12), screenFrame.maxY - panelSize.height - 12)

        panel.setFrameOrigin(origin)
        panel.setContentSize(Self.contentSize)
        AppDiagnostics.log("profile editor positioned at: \(panel.frame), parent: \(String(describing: parentWindow?.frame))")
    }
}
