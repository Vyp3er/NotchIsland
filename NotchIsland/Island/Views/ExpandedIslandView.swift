import SwiftUI

/// Inhalt der geöffneten Island: Kopfzeile mit Tabs und darunter der aktive Tab.
struct ExpandedIslandView: View {
    @EnvironmentObject private var model: IslandViewModel

    var body: some View {
        VStack(spacing: 8) {
            IslandHeaderView()
                .frame(height: model.headerHeight)

            ZStack {
                TabContentView(tab: model.selectedTab)
                    .id(model.selectedTab)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, model.contentHorizontalPadding)
        .padding(.bottom, 14)
    }
}

/// Kopfzeile: links die Tab-Icons, in der Mitte frei für die Notch, rechts Aktionen und Zahnrad.
struct IslandHeaderView: View {
    @EnvironmentObject private var model: IslandViewModel

    var body: some View {
        HStack(spacing: 0) {
            IslandTabBar()
                .frame(width: model.headerSideWidth, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                TabHeaderActions(tab: model.selectedTab)
                HeaderIconButton(systemImage: "gearshape.fill", help: "Einstellungen") {
                    model.openSettings()
                }
            }
            .frame(width: model.headerSideWidth, alignment: .trailing)
        }
    }
}

struct IslandTabBar: View {
    @EnvironmentObject private var model: IslandViewModel
    @EnvironmentObject private var settings: AppSettings
    @Namespace private var namespace

    var body: some View {
        let tabs = settings.visibleTabs
        // Breite pro Icon so wählen, dass die Leiste nie unter die Notch ragt.
        let count = CGFloat(max(tabs.count, 1))
        let spacing: CGFloat = tabs.count > 5 ? 1 : 2
        let buttonWidth = max(20, min(30, (model.headerSideWidth - (count - 1) * spacing) / count))
        HStack(spacing: spacing) {
            ForEach(tabs) { tab in
                let selected = model.selectedTab == tab
                Button {
                    model.select(tab)
                    // Bewusst angeklickt: Eingabefeld direkt bereit machen.
                    if tab == .timer { model.focusTextInput() }
                } label: {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
                        .frame(width: buttonWidth, height: 24)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .matchedGeometryEffect(id: "selectedTab", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
    }
}

/// Kleiner runder Icon-Button für die Kopfzeile.
struct HeaderIconButton: View {
    let systemImage: String
    let help: String
    var role: ButtonRole?
    var tint: Color?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint.map { $0.opacity(hovering ? 1 : 0.85) } ?? Color.white.opacity(hovering ? 0.95 : 0.55))
                .frame(width: 24, height: 24)
                .background(Circle().fill((tint ?? Color.white).opacity(hovering ? 0.22 : 0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// Wählt die Ansicht des aktiven Tabs.
struct TabContentView: View {
    let tab: IslandTab

    var body: some View {
        switch tab {
        case .shelf: ShelfView()
        case .music: MusicView()
        case .camera: CameraTabView()
        case .calendar: CalendarTabView()
        case .clipboard: ClipboardView()
        case .macBuddy: MacBuddyTabView()
        case .timer: TimerTabView()
        }
    }
}

/// Tab-spezifische Aktionen rechts in der Kopfzeile.
struct TabHeaderActions: View {
    let tab: IslandTab

    var body: some View {
        switch tab {
        case .shelf: ShelfHeaderActions()
        case .music: MusicHeaderActions()
        case .camera: EmptyView()
        case .calendar: CalendarHeaderActions()
        case .clipboard: ClipboardHeaderActions()
        case .macBuddy: MacBuddyHeaderActions()
        case .timer: TimerHeaderActions()
        }
    }
}
