import SwiftUI

struct PathPicker: View {
    @Binding var path: String
    let label: String
    let chooseFiles: Bool
    let chooseDirectories: Bool

    init(path: Binding<String>, label: String, chooseFiles: Bool = true, chooseDirectories: Bool = true) {
        self._path = path
        self.label = label
        self.chooseFiles = chooseFiles
        self.chooseDirectories = chooseDirectories
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 60, alignment: .trailing)
            TextField("选择路径...", text: $path)
                .textFieldStyle(.roundedBorder)
            Button("浏览") {
                browse()
            }
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = chooseFiles
        panel.canChooseDirectories = chooseDirectories
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            path = panel.url?.path ?? path
        }
    }
}
