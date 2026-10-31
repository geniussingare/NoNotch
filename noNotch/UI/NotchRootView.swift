import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @Bindable var viewModel: NotchViewModel
    @AppStorage(SettingsKey.theme) private var theme = SettingsDefaults.theme
    // Observed so the shape re-measures when the user changes Panel size.
    @AppStorage(SettingsKey.panelScale) private var panelScale = SettingsDefaults.panelScale
    // Observed so Home re-measures when its cards change.
    @AppStorage(SettingsKey.homeCards) private var homeCards = Data()

    var body: some View {
        if viewModel.showsPullCord {
            PullCord { viewModel.expand() }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
        } else {
            island
        }
    }

    private var island: some View {
        let shape = NotchShape(topRadius: viewModel.topRadius, bottomRadius: viewModel.bottomRadius)
        let size = viewModel.shapeSize

        return ZStack(alignment: .top) {
            NotchBackground(
                theme: theme,
                isOpen: viewModel.isExpanded || viewModel.isNotificationBanner,
                notchHeight: viewModel.geometry.notchSize.height,
                shape: shape
            )

            if viewModel.isExpanded {
                ExpandedView(viewModel: viewModel)
                    .frame(width: viewModel.tab.contentSize.width, height: viewModel.tab.contentSize.height)
                    .scaleEffect(panelScale, anchor: .top)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .transition(.asymmetric(
                        insertion: .islandContent.animation(NotchViewModel.spring.delay(0.04)),
                        removal: .islandContent.animation(.easeOut(duration: 0.12))
                    ))
            } else if case .activity(.notification(let item)) = viewModel.wing {
                NotificationBanner(item: item, notchHeight: viewModel.geometry.notchSize.height)
                    .padding(.horizontal, viewModel.topRadius)
                    .transition(.islandContent.animation(NotchViewModel.spring))
                    .onTapGesture { viewModel.expand(to: .notifications) }
            } else if let wing = viewModel.wing {
                CollapsedWings(viewModel: viewModel, wing: wing)
                    .padding(.horizontal, viewModel.topRadius)
                    .transition(.islandContent.animation(NotchViewModel.spring))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .shadow(color: .black.opacity(viewModel.isExpanded ? 0.35 : 0), radius: 12, y: 6)
        .contentShape(shape)
        // Only while collapsed: an always-on parent tap can swallow clicks meant for buttons inside.
        .gesture(TapGesture().onEnded { viewModel.expand() }, including: viewModel.isExpanded ? .subviews : .all)
        .onDrop(of: [.fileURL], isTargeted: $viewModel.isDropTargeted) { providers in
            loadFiles(from: providers)
            return true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchViewModel.spring, value: theme)
        .animation(NotchViewModel.spring, value: panelScale)
        .animation(NotchViewModel.spring, value: homeCards)
        .onChange(of: panelScale) { viewModel.expand() }
        .animation(NotchViewModel.spring, value: viewModel.wing)
        .animation(NotchViewModel.spring, value: viewModel.isDropTargeted)
        .environment(\.colorScheme, .dark)
    }

    private func loadFiles(from providers: [NSItemProvider]) {
        let shelf = viewModel.services.shelf
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    withAnimation(NotchViewModel.spring) { shelf.add([url]) }
                }
            }
        }
        viewModel.expand(to: .shelf)
    }
}

// MARK: - iOS-style island transition

/// Content inside the island blurs, shrinks toward the notch and fades,
/// the way Dynamic Island content morphs on iPhone.
private struct IslandContentModifier: ViewModifier {
    let progress: Double // 0 = hidden, 1 = shown

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.86 + 0.14 * progress, anchor: .top)
            .blur(radius: 10 * (1 - progress))
            .opacity(progress)
    }
}

extension AnyTransition {
    static var islandContent: AnyTransition {
        .modifier(active: IslandContentModifier(progress: 0), identity: IslandContentModifier(progress: 1))
    }
}
