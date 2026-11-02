// Basiert auf MacBuddy/NotchIslandIntegration/MacBuddyIslandViews.swift, angepasst an das
// Island-Design: Live-Aktivität links/rechts der Notch und ein eigener Tab.

import SwiftUI

/// Symbole, Farben und Texte für die MacBuddy-Zustände.
@MainActor
enum MacBuddyStyle {
    static func symbol(for client: MacBuddyIslandClient) -> String {
        if client.confirmation != nil { return "exclamationmark.shield.fill" }
        if let result = client.result, client.status == nil || client.status?.state == .done || client.status?.state == .failed {
            return result.success ? "checkmark.circle.fill" : "xmark.octagon.fill"
        }
        switch client.status?.state {
        case .listening: return "waveform"
        case .thinking: return "sparkles"
        case .working: return "cursorarrow.rays"
        case .awaitingConfirmation: return "exclamationmark.shield.fill"
        case .failed: return "xmark.octagon.fill"
        case .done: return "checkmark.circle.fill"
        case .cancelled: return "stop.circle"
        default: return "cursorarrow.rays"
        }
    }

    static func tint(for client: MacBuddyIslandClient) -> Color {
        if client.confirmation != nil { return .orange }
        switch client.status?.state {
        case .failed: return .red
        case .done: return .green
        case .cancelled: return .gray
        case .awaitingConfirmation: return .orange
        default:
            if let result = client.result { return result.success ? .green : .red }
            return .accentColor
        }
    }

    static func label(for state: MacBuddyIsland.State) -> String {
        switch state {
        case .idle: "Bereit"
        case .listening: "Hört zu"
        case .thinking: "Denkt nach"
        case .working: "Arbeitet"
        case .awaitingConfirmation: "Wartet auf Bestätigung"
        case .done: "Fertig"
        case .failed: "Fehlgeschlagen"
        case .cancelled: "Abgebrochen"
        }
    }

    /// Läuft gerade etwas (für pulsierende Symbole)?
    static func isBusy(_ client: MacBuddyIslandClient) -> Bool {
        switch client.status?.state {
        case .listening, .thinking, .working: true
        default: false
        }
    }
}

// MARK: - Tab

/// MacBuddy-Tab: Bestätigung, Ergebnis, laufender Status oder Bereitschaft.
struct MacBuddyTabView: View {
    @EnvironmentObject private var macBuddy: MacBuddyIslandClient
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            if !settings.macBuddyEnabled {
                MacBuddyMessageView(
                    symbol: "cursorarrow.rays",
                    title: "MacBuddy-Anbindung ist aus",
                    detail: "Einschalten unter Einstellungen → MacBuddy.",
                    buttonTitle: nil,
                    action: {}
                )
            } else if let confirmation = macBuddy.confirmation {
                MacBuddyConfirmationView(confirmation: confirmation)
            } else if let result = macBuddy.result {
                MacBuddyResultView(result: result)
            } else if let status = macBuddy.status {
                MacBuddyStatusView(status: status)
            } else {
                MacBuddyMessageView(
                    symbol: "cursorarrow.rays",
                    title: macBuddy.isMacBuddyRunning ? "MacBuddy ist bereit" : "MacBuddy läuft nicht",
                    detail: macBuddy.isMacBuddyRunning
                        ? "Ruf den Buddy mit deinem Kürzel (Standard ⌃⌘B). Status und Bestätigungen erscheinen hier."
                        : "Starte MacBuddy, damit Status, Ergebnisse und Bestätigungen hier erscheinen.",
                    buttonTitle: macBuddy.isMacBuddyRunning ? "MacBuddy öffnen" : (macBuddy.isMacBuddyInstalled ? "MacBuddy starten" : nil),
                    action: { macBuddy.openMacBuddy() }
                )
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: macBuddy.confirmation?.id)
        .animation(.easeInOut(duration: 0.2), value: macBuddy.result?.timestamp)
    }
}

/// Bestätigung einer riskanten Aktion: Ablehnen oder Ausführen.
private struct MacBuddyConfirmationView: View {
    let confirmation: MacBuddyIsland.ConfirmationRequest
    @EnvironmentObject private var macBuddy: MacBuddyIslandClient

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.18))
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .symbolEffect(.pulse)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(confirmation.category.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.orange)
                Text(confirmation.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                ScrollView(.vertical, showsIndicators: false) {
                    Text(confirmation.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 8) {
                    Spacer()
                    if !confirmation.allowsApproval {
                        Text("Bestätigen nur im MacBuddy-Panel")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    Button("Ablehnen") { macBuddy.deny() }
                        .buttonStyle(IslandPillButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    if confirmation.allowsApproval {
                        Button(confirmation.confirmLabel) { macBuddy.approve() }
                            .buttonStyle(IslandPillButtonStyle(tint: .orange))
                    }
                }
            }
        }
    }
}

/// Ergebnis einer Anfrage.
private struct MacBuddyResultView: View {
    let result: MacBuddyIsland.ResultMessage
    @EnvironmentObject private var macBuddy: MacBuddyIslandClient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(result.success ? Color.green : Color.red)
                Text(result.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Spacer()
                Text(result.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            ScrollView(.vertical, showsIndicators: false) {
                Text(result.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 8) {
                Spacer()
                Button("In MacBuddy öffnen") { macBuddy.openMacBuddy() }
                    .buttonStyle(IslandPillButtonStyle())
                Button("OK") { macBuddy.dismissResult() }
                    .buttonStyle(IslandPillButtonStyle(tint: .white))
            }
        }
    }
}

/// Laufender Status mit großem Not-Aus.
private struct MacBuddyStatusView: View {
    let status: MacBuddyIsland.StatusMessage
    @EnvironmentObject private var macBuddy: MacBuddyIslandClient

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(MacBuddyStyle.tint(for: macBuddy).opacity(0.18))
                Image(systemName: MacBuddyStyle.symbol(for: macBuddy))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(MacBuddyStyle.tint(for: macBuddy))
                    .symbolEffect(.pulse, isActive: MacBuddyStyle.isBusy(macBuddy))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text("MACBUDDY · \(MacBuddyStyle.label(for: status.state).uppercased())")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(MacBuddyStyle.tint(for: macBuddy))
                Text(status.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                if let detail = status.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(2)
                }
                if let progress = status.progress {
                    // Eigener Balken: System-Controls erscheinen im nie aktiven Island-Fenster grau.
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule()
                                .fill(MacBuddyStyle.tint(for: macBuddy))
                                .frame(width: proxy.size.width * min(1, max(0, progress)))
                        }
                    }
                    .frame(height: 5)
                    .padding(.top, 6)
                    .animation(.easeOut(duration: 0.3), value: progress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if status.canStop {
                Button {
                    macBuddy.stopMacBuddy()
                } label: {
                    Label("Stopp", systemImage: "stop.fill")
                }
                .buttonStyle(IslandPillButtonStyle(tint: .red))
                .help("MacBuddy sofort stoppen (Not-Aus)")
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct MacBuddyMessageView: View {
    let symbol: String
    let title: String
    let detail: String
    let buttonTitle: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
            if let buttonTitle {
                Button(buttonTitle, action: action)
                    .buttonStyle(IslandPillButtonStyle())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Kopfzeile: Not-Aus, solange etwas läuft.
struct MacBuddyHeaderActions: View {
    @EnvironmentObject private var macBuddy: MacBuddyIslandClient

    var body: some View {
        if macBuddy.canStop {
            HeaderIconButton(systemImage: "stop.fill", help: "MacBuddy sofort stoppen", tint: .red) {
                macBuddy.stopMacBuddy()
            }
        }
    }
}

// MARK: - Live-Aktivität

/// Zugeklappt, links: Symbol und Status.
struct MacBuddyCompactLeading: View {
    @EnvironmentObject private var macBuddy: MacBuddyIslandClient

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: MacBuddyStyle.symbol(for: macBuddy))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(MacBuddyStyle.tint(for: macBuddy))
                .symbolEffect(.pulse, isActive: MacBuddyStyle.isBusy(macBuddy) || macBuddy.confirmation != nil)
                .contentTransition(.symbolEffect(.replace))
            Text(macBuddy.confirmation?.title ?? macBuddy.status?.title ?? macBuddy.result?.title ?? "MacBuddy")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Zugeklappt, rechts: Not-Aus (direkt klickbar) oder das Ergebnis.
struct MacBuddyCompactTrailing: View {
    @EnvironmentObject private var macBuddy: MacBuddyIslandClient
    @EnvironmentObject private var island: IslandViewModel

    var body: some View {
        Group {
            if macBuddy.canStop {
                HStack(spacing: 4) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Stopp")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.red)
                .scaleEffect(island.isPointerOnCompactAction ? 1.12 : 1, anchor: .trailing)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: island.isPointerOnCompactAction)
            } else if let status = macBuddy.status {
                Text(MacBuddyStyle.label(for: status.state))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacBuddyStyle.tint(for: macBuddy))
                    .lineLimit(1)
            } else if let result = macBuddy.result {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(result.success ? Color.green : Color.red)
            }
        }
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}
