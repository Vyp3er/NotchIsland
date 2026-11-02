import SwiftUI

/// Musik-Tab: Cover, Titel, Fortschritt und Steuerung.
struct MusicView: View {
    @EnvironmentObject private var nowPlaying: NowPlayingService

    var body: some View {
        if let info = nowPlaying.info {
            NowPlayingPanel(info: info)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                Text("Keine Wiedergabe")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(nowPlaying.backend == .appleScript
                     ? "Starte Musik oder Spotify"
                     : "Starte Musik, Spotify oder ein Video im Browser")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct NowPlayingPanel: View {
    let info: NowPlayingInfo
    @EnvironmentObject private var nowPlaying: NowPlayingService

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = min(proxy.size.height, 132)
            HStack(spacing: 18) {
                ArtworkView(info: info, size: artworkSize)
                    .onTapGesture { nowPlaying.openSourceApp() }
                    .help("App öffnen")

                VStack(alignment: .leading, spacing: 0) {
                    Text(info.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text([info.artist, info.album].filter { !$0.isEmpty }.joined(separator: " – "))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                        .padding(.top, 2)

                    Spacer(minLength: 8)

                    PlaybackProgressView(info: info, tint: nowPlaying.accentColor)

                    Spacer(minLength: 8)

                    HStack(spacing: 28) {
                        ControlButton(systemImage: "backward.fill", size: 17) { nowPlaying.previousTrack() }
                        ControlButton(systemImage: info.isPlaying ? "pause.fill" : "play.fill", size: 26) {
                            nowPlaying.togglePlayPause()
                        }
                        ControlButton(systemImage: "forward.fill", size: 17) { nowPlaying.nextTrack() }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct ArtworkView: View {
    let info: NowPlayingInfo
    let size: CGFloat
    @EnvironmentObject private var nowPlaying: NowPlayingService

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let artwork = info.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: size * 0.32, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: nowPlaying.accentColor.opacity(0.35), radius: 14, y: 4)
            .scaleEffect(info.isPlaying ? 1 : 0.92)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: info.isPlaying)

            if let icon = nowPlaying.sourceAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .offset(x: 6, y: 6)
            }
        }
    }
}

/// Fortschrittsbalken mit Zeiten; ziehen zum Spulen.
private struct PlaybackProgressView: View {
    let info: NowPlayingInfo
    let tint: Color
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @State private var scrubFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = info.duration ?? 0
            let elapsed = info.elapsed(at: context.date) ?? 0
            let fraction = scrubFraction ?? (duration > 0 ? min(1, elapsed / duration) : 0)

            VStack(spacing: 5) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule()
                            .fill(tint)
                            .frame(width: max(0, proxy.size.width * fraction))
                    }
                    .frame(height: scrubFraction == nil ? 5 : 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard duration > 0 else { return }
                                scrubFraction = min(1, max(0, value.location.x / proxy.size.width))
                            }
                            .onEnded { _ in
                                if let scrubFraction, duration > 0 {
                                    nowPlaying.seek(to: scrubFraction * duration)
                                }
                                scrubFraction = nil
                            }
                    )
                    .animation(.easeOut(duration: 0.15), value: scrubFraction == nil)
                }
                .frame(height: 10)

                HStack {
                    Text(Self.format(duration > 0 ? fraction * duration : elapsed))
                    Spacer()
                    Text(duration > 0 ? "-" + Self.format(max(0, duration - fraction * duration)) : "")
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.45))
            }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

private struct ControlButton: View {
    let systemImage: String
    let size: CGFloat
    let action: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.white.opacity(hovering ? 1 : 0.85))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + 18, height: size + 14)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
                .scaleEffect(pressed ? 0.88 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Kopfzeile: Name der abspielenden App.
struct MusicHeaderActions: View {
    @EnvironmentObject private var nowPlaying: NowPlayingService

    var body: some View {
        if nowPlaying.info != nil, let name = nowPlaying.sourceAppName {
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1)
        }
    }
}
