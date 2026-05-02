import SwiftUI

struct LogConsoleView: View {
    let lines: [LogLine]
    private let bottomID = "log-console-bottom"

    fileprivate static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        LogLineRow(line: line)
                            .id(line.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .cornerRadius(4)
            .onAppear {
                scrollToBottom(proxy)
            }
            .onChange(of: lines.count) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
    }
}

private struct LogLineRow: View {
    let line: LogLine

    var body: some View {
        Text("[\(line.timestamp, formatter: LogConsoleView.timeFormatter)] [\(line.level.rawValue.uppercased())] \(line.message)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(colorForLevel(line.level))
            .textSelection(.enabled)
    }

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .debug:    return .secondary
        case .info:     return .primary
        case .warning:  return .orange
        case .error:    return .red
        }
    }
}
