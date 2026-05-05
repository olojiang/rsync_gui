import AppKit
import Foundation

struct FinderSyncDraft: Equatable {
    static let defaultOptions = ["-a", "--human-readable", "--info=progress2"]

    let sourcePath: String
    let destinationPath: String

    var profile: RsyncProfile {
        RsyncProfile(
            name: Self.profileName(sourcePath: sourcePath, destinationPath: destinationPath),
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            options: Self.defaultOptions
        )
    }

    static func profileName(sourcePath: String, destinationPath: String) -> String {
        let sourceName = URL(fileURLWithPath: sourcePath).lastPathComponent
        let destinationName = URL(fileURLWithPath: destinationPath).lastPathComponent
        return "Finder 同步: \(sourceName) -> \(destinationName)"
    }
}

enum FinderSelectionError: LocalizedError, Equatable {
    case noSelection
    case multipleSelection
    case notDirectory(String)
    case missingSource

    var errorDescription: String? {
        switch self {
        case .noSelection:
            return "没有收到 Finder 选择项。请在 Finder 中右键一个文件夹。"
        case .multipleSelection:
            return "当前只支持选择一个来源文件夹和一个目标文件夹。"
        case .notDirectory(let path):
            return "选择项不是文件夹: \(path)"
        case .missingSource:
            return "还没有选择来源。请先在 Finder 中右键来源文件夹，选择“Rsync 纪 > 设为同步来源”。"
        }
    }
}

enum FinderSelectionParser {
    static func firstDirectoryPath(from urls: [URL], fileManager: FileManager = .default) throws -> String {
        guard !urls.isEmpty else { throw FinderSelectionError.noSelection }
        guard urls.count == 1, let url = urls.first else { throw FinderSelectionError.multipleSelection }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FinderSelectionError.notDirectory(url.path)
        }

        return url.path
    }
}

@MainActor
final class FinderSyncServiceProvider: NSObject {
    private static let pendingSourceKey = "FinderSyncPendingSourcePath"

    private let store: any ProfileStoreProtocol
    private let executor: any RsyncExecutorProtocol
    private var quickSyncWindowController: QuickSyncWindowController?

    init(store: any ProfileStoreProtocol, executor: any RsyncExecutorProtocol) {
        self.store = store
        self.executor = executor
    }

    @objc func setSyncSource(_ pasteboard: NSPasteboard, userData: String?, error serviceError: AutoreleasingUnsafeMutablePointer<NSString>) {
        do {
            let sourcePath = try FinderSelectionParser.firstDirectoryPath(from: selectedFileURLs(from: pasteboard))
            UserDefaults.standard.set(sourcePath, forKey: Self.pendingSourceKey)
            showAlert(
                title: "已选择同步来源",
                message: "\(sourcePath)\n\n接下来在 Finder 中右键目标文件夹，选择“Rsync 纪 > 设为同步目标并确认”。"
            )
        } catch {
            report(error, to: serviceError)
        }
    }

    @objc func setSyncDestinationAndConfirm(_ pasteboard: NSPasteboard, userData: String?, error serviceError: AutoreleasingUnsafeMutablePointer<NSString>) {
        do {
            guard let sourcePath = UserDefaults.standard.string(forKey: Self.pendingSourceKey), !sourcePath.isEmpty else {
                throw FinderSelectionError.missingSource
            }

            let destinationPath = try FinderSelectionParser.firstDirectoryPath(from: selectedFileURLs(from: pasteboard))
            let draft = FinderSyncDraft(sourcePath: sourcePath, destinationPath: destinationPath)
            UserDefaults.standard.removeObject(forKey: Self.pendingSourceKey)
            showQuickSyncWindow(profile: draft.profile)
        } catch {
            report(error, to: serviceError)
        }
    }

    private func selectedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return urls
        }

        let filenameType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        guard let filenames = pasteboard.propertyList(forType: filenameType) as? [String] else {
            return []
        }
        return filenames.map { URL(fileURLWithPath: $0) }
    }

    private func showQuickSyncWindow(profile: RsyncProfile) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let controller = QuickSyncWindowController(
            profile: profile,
            store: store,
            executor: executor,
            onClose: { [weak self] in
                self?.quickSyncWindowController = nil
            }
        )
        quickSyncWindowController = controller
        controller.show()
    }

    private func showAlert(title: String, message: String) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func report(_ caughtError: Error, to serviceError: AutoreleasingUnsafeMutablePointer<NSString>) {
        let message = caughtError.localizedDescription
        serviceError.pointee = message as NSString
        showAlert(title: "Rsync 纪 Finder 操作失败", message: message)
    }
}
