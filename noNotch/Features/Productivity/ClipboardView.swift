import SwiftUI

struct ClipboardView: View {
    let clipboard: ClipboardHistory
    @State private var copiedID: UUID?

    var body: some View {
        if clipboard.entries.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 16, weight: .medium))
                Text("Copied items appear here")
                    .font(Design.text(12, .medium))
            }
            .foregroundStyle(Design.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(clipboard.entries) { entry in
                            ClipCard(entry: entry, copied: copiedID == entry.id) {
                                clipboard.copy(entry)
                                copiedID = entry.id
                            }
                            .contextMenu { Button("Remove") { clipboard.remove(entry) } }
                        }
                    }
                }
                IconButton(symbol: "trash", size: 11, halo: 28, tint: Design.secondaryText) {
                    withAnimation(NotchViewModel.spring) { clipboard.clear() }
                }
                .help("Clear history")
            }
        }
    }
}

private struct ClipCard: View {
    let entry: ClipboardHistory.Entry
    let copied: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(spacing: 4) {
                    if let icon = entry.sourceApp {
                        Image(nsImage: icon).resizable().frame(width: 11, height: 11)
                    }
                    Text(copied ? "Copied" : entry.date.formatted(.relative(presentation: .numeric)))
                        .font(Design.text(9))
                        .foregroundStyle(copied ? .green : Design.tertiaryText)
                }
            }
            .padding(8)
            .frame(width: 112, height: 80)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0.06)))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(NotchViewModel.snappy, value: hovering)
    }

    @ViewBuilder
    private var preview: some View {
        switch entry.content {
        case .text(let text):
            Text(text)
                .font(.system(size: 10.5, design: isCode(text) ? .monospaced : .default))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .files(let urls):
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: urls[0].path))
                    .resizable()
                    .frame(width: 26, height: 26)
                Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")
                    .font(Design.text(10, .medium))
                    .lineLimit(2)
            }
        }
    }

    private func isCode(_ text: String) -> Bool {
        text.contains("{") || text.contains(";") || text.hasPrefix("$ ") || text.contains("func ") || text.contains("=>")
    }
}
