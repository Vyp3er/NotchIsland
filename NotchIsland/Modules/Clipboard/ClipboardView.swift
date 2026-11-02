import SwiftUI

/// Zwischenablage-Tab: Karten der letzten Einträge. Klick kopiert, Ziehen fügt woanders ein.
struct ClipboardView: View {
    @EnvironmentObject private var clipboard: ClipboardHistoryStore

    var body: some View {
        if clipboard.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                Text("Noch nichts kopiert")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("Kopierte Texte, Links und Bilder erscheinen hier. Passwörter werden ignoriert.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(clipboard.sortedItems) { item in
                        ClipboardCard(item: item, isCopied: clipboard.lastCopiedID == item.id)
                            .frame(width: 138)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 2)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: clipboard.sortedItems.map(\.id))
        }
    }
}

private struct ClipboardCard: View {
    let item: ClipboardItem
    let isCopied: Bool

    @EnvironmentObject private var clipboard: ClipboardHistoryStore
    @State private var hovering = false
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: isCopied ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isCopied ? Color.green : Color.white.opacity(0.55))
                    .contentTransition(.symbolEffect(.replace))
                Text(isCopied ? "Kopiert" : item.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(isCopied ? 0.9 : 0.45))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item.isPinned || hovering {
                    Button {
                        clipboard.togglePin(item)
                    } label: {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(item.isPinned ? Color.orange : Color.white.opacity(0.6))
                            .rotationEffect(.degrees(item.isPinned ? 0 : 35))
                    }
                    .buttonStyle(.plain)
                    .help(item.isPinned ? "Lösen" : "Anheften")
                }
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.11 : 0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(item.isPinned ? Color.orange.opacity(0.45) : Color.clear, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { clipboard.copy(item) }
        .onHover { hovering = $0 }
        .onDrag { clipboard.itemProvider(for: item) }
        .contextMenu {
            Button("Kopieren") { clipboard.copy(item) }
            Button(item.isPinned ? "Lösen" : "Anheften") { clipboard.togglePin(item) }
            Divider()
            Button("Löschen", role: .destructive) { clipboard.delete(item) }
        }
        .help("Klicken zum Kopieren, ziehen zum Einfügen")
        .animation(.easeOut(duration: 0.12), value: hovering)
        .task(id: item.imageFileName) {
            guard item.kind == .image, let url = item.imageURL else { return }
            thumbnail = await ThumbnailCache.shared.thumbnail(for: url, size: 240)
        }
    }

    private var icon: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .files: "doc"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            Text(item.previewText.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(6)
        case .link:
            VStack(alignment: .leading, spacing: 3) {
                Text(item.linkURL?.host ?? "Link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(item.previewText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(4)
            }
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
        case .files:
            HStack(alignment: .top, spacing: 6) {
                if let first = item.fileURLs.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                        .resizable()
                        .frame(width: 28, height: 28)
                }
                Text(item.previewText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(5)
            }
        }
    }
}

struct ClipboardHeaderActions: View {
    @EnvironmentObject private var clipboard: ClipboardHistoryStore

    var body: some View {
        if !clipboard.items.isEmpty {
            Text("\(clipboard.items.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.5))
            HeaderIconButton(systemImage: "trash.fill", help: "Verlauf leeren (angeheftete bleiben)") {
                clipboard.clear()
            }
        }
    }
}
