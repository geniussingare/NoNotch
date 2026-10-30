import SwiftUI

struct ShelfView: View {
    let shelf: FileShelf
    let isTargeted: Bool

    var body: some View {
        if shelf.items.isEmpty || isTargeted {
            DropZone(isTargeted: isTargeted)
        } else {
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item, shelf: shelf)
                                .transition(.scale(0.8).combined(with: .opacity))
                        }
                    }
                }
                VStack(spacing: 2) {
                    IconButton(symbol: "airplayaudio", size: 12, halo: 28, tint: Design.secondaryText) {
                        shelf.airDrop(shelf.items.map(\.url))
                    }
                    .help("AirDrop all")
                    IconButton(symbol: "trash", size: 11, halo: 28, tint: Design.secondaryText) {
                        withAnimation(NotchViewModel.spring) { shelf.clear() }
                    }
                    .help("Clear shelf")
                }
            }
        }
    }
}

private struct ShelfTile: View {
    let item: FileShelf.Item
    let shelf: FileShelf
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
            Text(item.url.lastPathComponent)
                .font(Design.text(9.5))
                .foregroundStyle(Design.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Design.fill : .clear))
        .overlay(alignment: .topTrailing) {
            if hovering {
                IconButton(symbol: "xmark.circle.fill", size: 11, halo: 16, tint: Design.secondaryText) {
                    withAnimation(NotchViewModel.spring) { shelf.remove(item) }
                }
                .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(NotchViewModel.snappy, value: hovering)
        .onTapGesture(count: 2) { shelf.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Show in Finder") { shelf.reveal(item) }
            Button("AirDrop") { shelf.airDrop([item.url]) }
            Divider()
            Button("Remove") { shelf.remove(item) }
        }
        .help("Drag out to use · double-click to open")
    }
}

private struct DropZone: View {
    let isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(isTargeted ? 0.5 : 0.15), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(isTargeted ? 0.06 : 0)))
            .overlay {
                HStack(spacing: 8) {
                    Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray")
                        .font(.system(size: 16, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                    Text(isTargeted ? "Drop to keep it here" : "Drag files here to hold them")
                        .font(Design.text(12, .medium))
                }
                .foregroundStyle(isTargeted ? .white : Design.secondaryText)
            }
            .animation(NotchViewModel.snappy, value: isTargeted)
    }
}
