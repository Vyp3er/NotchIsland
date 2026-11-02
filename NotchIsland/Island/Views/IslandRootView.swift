import SwiftUI

/// Wurzel der Island: zeichnet die schwarze Form und wechselt zwischen zugeklappt, Live-Aktivität und geöffnet.
struct IslandRootView: View {
    @EnvironmentObject private var model: IslandViewModel
    @EnvironmentObject private var shelf: ShelfStore

    var body: some View {
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
    }

    private var island: some View {
        let expanded = model.isExpanded
        let size = model.currentFrameSize
        let shape = NotchShape(
            topRadius: expanded ? model.expandedTopRadius : model.collapsedTopRadius,
            bottomRadius: expanded ? model.expandedBottomRadius : model.collapsedBottomRadius
        )

        return ZStack(alignment: .top) {
            shape.fill(Color.black)

            // Der Inhalt hat immer die volle Größe und wird von der Form beschnitten: so springt
            // beim Auf-/Zuklappen nichts um. Läuft ein Drag aus der Ablage, bleibt er geladen.
            if expanded || shelf.isDraggingOut {
                ExpandedIslandView()
                    .frame(width: model.expandedFrameSize.width, height: model.expandedFrameSize.height, alignment: .top)
                    .opacity(expanded ? 1 : 0)
                    .allowsHitTesting(expanded)
                    .transition(.islandContent)
            } else if model.compactActivity != .none {
                CompactActivityView()
                    .transition(.compactActivity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .scaleEffect(model.isPeeking ? 1.06 : 1, anchor: .top)
        .overlay {
            shape
                .stroke(Color.accentColor.opacity(model.isDropTargeted ? 0.9 : 0), lineWidth: 2)
                .padding(1)
        }
        .shadow(color: .black.opacity(expanded ? 0.55 : 0), radius: expanded ? 20 : 0, y: expanded ? 10 : 0)
        .animation(.easeOut(duration: 0.15), value: model.isDropTargeted)
    }
}

// MARK: - Übergänge

private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    /// Inhalt der geöffneten Island: wächst aus der Notch, mit leichter Unschärfe.
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.9, anchor: .top))
                .combined(with: .modifier(active: BlurModifier(radius: 10), identity: BlurModifier(radius: 0)))
                .animation(.spring(response: 0.42, dampingFraction: 0.86).delay(0.05)),
            removal: .opacity
                .combined(with: .scale(scale: 0.94, anchor: .top))
                .combined(with: .modifier(active: BlurModifier(radius: 6), identity: BlurModifier(radius: 0)))
                .animation(.easeOut(duration: 0.14))
        )
    }

    static var compactActivity: AnyTransition {
        .opacity
            .combined(with: .modifier(active: BlurModifier(radius: 6), identity: BlurModifier(radius: 0)))
            .animation(.easeInOut(duration: 0.25))
    }
}

// MARK: - Umgebungsobjekte

extension View {
    /// Stellt alle Dienste der App als EnvironmentObjects bereit.
    @MainActor
    func withAppEnvironment(_ environment: AppEnvironment) -> some View {
        self
            .environmentObject(environment.settings)
            .environmentObject(environment.island)
            .environmentObject(environment.shelf)
            .environmentObject(environment.nowPlaying)
            .environmentObject(environment.camera)
            .environmentObject(environment.calendar)
            .environmentObject(environment.clipboard)
            .environmentObject(environment.macBuddy)
            .environmentObject(environment.timers)
    }
}
