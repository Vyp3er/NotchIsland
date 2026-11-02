import SwiftUI

/// Live-Aktivität im zugeklappten Zustand: links und rechts neben der Notch.
struct CompactActivityView: View {
    @EnvironmentObject private var model: IslandViewModel

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: model.earWidth, height: model.notchHeight)
            Color.clear
                .frame(width: model.notchWidth)
            trailing
                .frame(width: model.earWidth, height: model.notchHeight)
        }
        .padding(.horizontal, model.collapsedTopRadius)
    }

    @ViewBuilder
    private var leading: some View {
        switch model.compactActivity {
        case .none: EmptyView()
        case .music: CompactMusicLeading()
        case .calendar: CompactCalendarLeading()
        case .macBuddy: MacBuddyCompactLeading()
        case .timer: CompactTimerLeading()
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch model.compactActivity {
        case .none: EmptyView()
        case .music: CompactMusicTrailing()
        case .calendar: CompactCalendarTrailing()
        case .macBuddy: MacBuddyCompactTrailing()
        case .timer: CompactTimerTrailing()
        }
    }
}
