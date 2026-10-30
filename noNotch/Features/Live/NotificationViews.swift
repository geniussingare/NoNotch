import SwiftUI

/// iOS-style banner that grows out of the notch for an incoming notification.
struct NotificationBanner: View {
    let item: NotificationMirror.Item
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: 10) {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(item.title)
                            .font(Design.text(12.5, .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(item.appName)
                            .font(Design.text(10))
                            .foregroundStyle(Design.tertiaryText)
                            .lineLimit(1)
                    }
                    if !item.body.isEmpty {
                        Text(item.body)
                            .font(Design.text(11.5))
                            .foregroundStyle(Design.secondaryText)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }
}

/// Recent notifications, newest first.
struct NotificationsView: View {
    let mirror: NotificationMirror

    var body: some View {
        Group {
            if mirror.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: Design.Icon.large, weight: .medium))
                    if AXIsProcessTrusted() {
                        Text("You're all caught up")
                            .font(Design.text(12, .medium))
                    } else {
                        Text("Notifications need Accessibility access")
                            .font(Design.text(12, .medium))
                        Button("Allow Access") { Permissions.shared.openSettings(for: .accessibility) }
                            .buttonStyle(PillButtonStyle(tint: .accentColor))
                    }
                }
                .foregroundStyle(Design.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(mirror.history) { item in
                                NotificationRow(item: item) { mirror.open(item) }
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                    }
                    IconButton(symbol: "trash", size: 11, halo: 26, tint: Design.secondaryText) {
                        withAnimation(NotchViewModel.spring) { mirror.clear() }
                    }
                    .help("Clear all")
                }
            }
        }
        .onAppear(perform: mirror.markRead)
        .animation(NotchViewModel.spring, value: mirror.history)
    }
}

private struct NotificationRow: View {
    let item: NotificationMirror.Item
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(nsImage: item.icon).resizable().frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(item.title).font(Design.text(11.5, .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(item.date, format: .relative(presentation: .numeric))
                            .font(Design.text(9))
                            .foregroundStyle(Design.tertiaryText)
                    }
                    if !item.body.isEmpty {
                        Text(item.body)
                            .font(Design.text(10.5))
                            .foregroundStyle(Design.secondaryText)
                            .lineLimit(2)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \(item.appName)")
    }
}
