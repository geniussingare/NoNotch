import SwiftUI

struct ExpandedView: View {
    @Bindable var viewModel: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: viewModel.geometry.notchSize.height)

            ZStack {
                switch viewModel.tab {
                case .home: HomeView(viewModel: viewModel)
                case .media: MediaView(viewModel: viewModel)
                case .controls: ControlsView(controls: viewModel.services.controls, hudActive: viewModel.services.hudActive) { viewModel.step(to: .mirror) }
                case .shelf: ShelfView(shelf: viewModel.services.shelf, isTargeted: viewModel.isDropTargeted)
                case .clipboard: ClipboardView(clipboard: viewModel.services.clipboard)
                case .notes: NotesView(notes: viewModel.services.notes, tasks: viewModel.services.tasks)
                case .calendar: CalendarGridView(calendar: viewModel.services.calendar) { viewModel.step(to: .home) }
                case .mirror: MirrorView { viewModel.step(to: .controls) }
                case .notifications: NotificationsView(mirror: viewModel.services.notifications)
                case .tasks: TasksView(viewModel: viewModel)
                case .taskDetail: TaskDetailView(viewModel: viewModel)
                case .upcoming: UpcomingView(viewModel: viewModel)
                case .taskDue: TaskDueView(viewModel: viewModel)
                case .insights: InsightsView(store: viewModel.services.tasks) { viewModel.step(to: .home) }
                }
            }
            .id(viewModel.tab)
            .transition(.opacity.animation(.easeOut(duration: 0.15)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .foregroundStyle(.white)
    }

    /// Sits beside the hardware notch: tabs on the left, status + settings on the right.
    private var header: some View {
        HStack(spacing: 0) {
            TabBar(selection: $viewModel.tab)
                .fixedSize()
            Spacer(minLength: viewModel.geometry.notchSize.width + 8)
            if UpdateChecker.shared.updateAvailable {
                UpdatePill()
                    .padding(.trailing, 6)
                    .transition(.scale.combined(with: .opacity))
            }
            HeaderStatus(services: viewModel.services)
            NotificationBell(mirror: viewModel.services.notifications) { viewModel.step(to: .notifications) }
            IconButton(symbol: "gearshape.fill", size: 10, halo: 20, tint: Design.tertiaryText, action: viewModel.openSettings)
        }
        .padding(.horizontal, 14)
    }
}

/// Compact glass "Update" button when a newer release is out.
private struct UpdatePill: View {
    var body: some View {
        Button(action: UpdateChecker.shared.openDownload) {
            Label("Update", systemImage: "arrow.down.circle.fill")
                .font(Design.text(9.5, .semibold))
                .padding(.horizontal, 7)
                .frame(height: 18)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .glassSurface(Capsule(), tint: .blue.opacity(0.45), interactive: true)
        .help("noNotch \(UpdateChecker.shared.latest ?? "") is available")
    }
}

private struct HeaderStatus: View {
    let services: Services

    var body: some View {
        HStack(spacing: 4) {
            if services.battery.hasBattery {
                Text("\(services.battery.level)%")
                    .font(Design.number(10, .medium))
                Image(systemName: batterySymbol)
                    .font(.system(size: 11))
                    .foregroundStyle(batteryColor)
            }
        }
        .foregroundStyle(Design.secondaryText)
    }

    private var batteryColor: Color {
        if services.battery.isCharging { return .green }
        return services.battery.level <= 20 ? .red : Design.secondaryText
    }

    private var batterySymbol: String {
        if services.battery.isCharging { return "battery.100percent.bolt" }
        switch services.battery.level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// Icon-only tabs with a small dot that glides under the active one.
struct TabBar: View {
    @Binding var selection: NotchTab
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NotchTab.barTabs) { tab in
                Button {
                    withAnimation(NotchViewModel.spring) { selection = tab }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: Design.Icon.small, weight: .semibold))
                        .foregroundStyle(selection == tab ? .white : Design.tertiaryText)
                        .frame(width: 15, height: 22)
                        .background {
                            if selection == tab {
                                Capsule()
                                    .fill(.clear)
                                    .glassSurface(Capsule(), tint: .white.opacity(0.14))
                                    .matchedGeometryEffect(id: "pill", in: indicator)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help(tab.title)
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
    }
}

private struct NotificationBell: View {
    let mirror: NotificationMirror
    let action: () -> Void

    var body: some View {
        IconButton(symbol: mirror.unread > 0 ? "bell.badge.fill" : "bell.fill", size: 10, halo: 20, tint: Design.tertiaryText, action: action)
            .overlay(alignment: .topTrailing) {
                if mirror.unread > 0 {
                    Text("\(min(mirror.unread, 9))")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 10, height: 10)
                        .background(Circle().fill(.red))
                        .offset(x: -1, y: 1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(NotchViewModel.snappy, value: mirror.unread)
            .help("Notifications")
    }
}
