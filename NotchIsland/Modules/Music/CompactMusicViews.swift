import SwiftUI

/// Zugeklappt, links neben der Notch: kleines Cover.
struct CompactMusicLeading: View {
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var island: IslandViewModel

    var body: some View {
        let size = max(16, island.notchHeight - 14)
        Group {
            if let artwork = nowPlaying.info?.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.15)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Zugeklappt, rechts neben der Notch: animierte Equalizer-Balken.
struct CompactMusicTrailing: View {
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var island: IslandViewModel

    var body: some View {
        EqualizerBars(isAnimating: nowPlaying.info?.isPlaying == true, color: nowPlaying.accentColor)
            .frame(width: 18, height: max(12, island.notchHeight - 20))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Vier Balken, die sich wie beim iPhone unregelmäßig bewegen (keine echten Pegel verfügbar).
struct EqualizerBars: View {
    let isAnimating: Bool
    let color: Color

    private let phases: [Double] = [0, 1.7, 0.9, 2.6]
    private let speeds: [Double] = [7.1, 9.3, 6.2, 8.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                HStack(alignment: .center, spacing: proxy.size.width * 0.12) {
                    ForEach(phases.indices, id: \.self) { index in
                        Capsule()
                            .fill(color)
                            .frame(height: proxy.size.height * level(index, time))
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func level(_ index: Int, _ time: TimeInterval) -> CGFloat {
        guard isAnimating else { return 0.2 }
        let t = time * speeds[index] / 4
        let value = 0.55 + 0.3 * sin(t + phases[index]) + 0.15 * sin(t * 2.3 + phases[index] * 1.9)
        return CGFloat(min(1, max(0.18, value)))
    }
}
