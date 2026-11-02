import SwiftUI

/// Ablage-Tab: Kacheln mit Vorschaubild, Drag & Drop rein und raus.
struct ShelfView: View {
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var island: IslandViewModel

    private let tileSize = CGSize(width: 86, height: 98)
    private let spacing: CGFloat = 6

    var body: some View {
        ZStack {
            if shelf.items.isEmpty {
                ShelfEmptyState(isTargeted: island.isDropTargeted)
                    .transition(.opacity)
            } else {
                grid
                    .transition(.opacity)
                if island.isDropTargeted {
                    dropOverlay
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: shelf.items)
        .animation(.easeOut(duration: 0.15), value: island.isDropTargeted)
    }

    private var grid: some View {
        GeometryReader { proxy in
            let rows = max(1, Int((proxy.size.height + spacing) / (tileSize.height + spacing)))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: Array(repeating: GridItem(.fixed(tileSize.height), spacing: spacing), count: rows),
                    spacing: spacing
                ) {
                    ForEach(shelf.items) { item in
                        ShelfItemTile(
                            item: item,
                            isSelected: shelf.selection.contains(item.id),
                            isInvalid: shelf.invalidIDs.contains(item.id)
                        )
                        .frame(width: tileSize.width, height: tileSize.height)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 2)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { shelf.clearSelection() }
            }
        }
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.accentColor.opacity(0.14))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
            .overlay {
                Label("Loslassen zum Ablegen", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
            }
            .allowsHitTesting(false)
    }
}

/// Leerer Zustand: gestrichelte Fläche als Einladung zum Ablegen.
struct ShelfEmptyState: View {
    let isTargeted: Bool

    var body: some View {
        let tint = isTargeted ? Color.accentColor : Color.white
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(tint.opacity(isTargeted ? 0.12 : 0.03))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint.opacity(isTargeted ? 0.9 : 0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "tray.and.arrow.down")
                        .font(.system(size: 24, weight: .medium))
                        .symbolEffect(.bounce, value: isTargeted)
                    Text(isTargeted ? "Loslassen zum Ablegen" : "Dateien hierher ziehen")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Dateien, Ordner, Bilder, Links und Text")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .foregroundStyle(isTargeted ? Color.accentColor : Color.white.opacity(0.75))
            }
    }
}

/// Eine Kachel der Ablage.
struct ShelfItemTile: View {
    let item: ShelfItem
    let isSelected: Bool
    let isInvalid: Bool

    @EnvironmentObject private var shelf: ShelfStore
    @State private var hovering = false
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 5) {
                preview
                    .frame(width: 54, height: 54)
                Text(item.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(isInvalid ? 0.4 : 0.9))
                    .strikethrough(isInvalid, color: Color.white.opacity(0.4))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isSelected ? 0.85 : 0), lineWidth: 1)
            }
            .overlay {
                TileInteractionView(
                    toolTip: isInvalid ? "Datei nicht gefunden: \(item.path)" : item.path,
                    onHover: { hovering = $0 },
                    onClick: { shelf.click(item.id, modifiers: $0) },
                    onDoubleClick: { shelf.open(item.id) },
                    onBeginDrag: { view, event in shelf.beginDrag(from: view, event: event, anchor: item.id) },
                    makeMenu: { shelf.contextMenu(for: item.id) }
                )
            }

            if hovering {
                Button {
                    shelf.remove(ids: [item.id])
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.black, Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .padding(4)
                .help("Aus Ablage entfernen")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .task(id: "\(item.path)|\(isInvalid)") {
            guard !isInvalid else { return }
            thumbnail = await ThumbnailCache.shared.thumbnail(for: item.url, size: 108)
        }
    }

    private var backgroundColor: Color {
        if isSelected { return Color.accentColor.opacity(0.28) }
        return Color.white.opacity(hovering ? 0.09 : 0.04)
    }

    @ViewBuilder
    private var preview: some View {
        if isInvalid {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: ThumbnailCache.shared.genericIcon(forPathExtension: item.pathExtension))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .saturation(0)
                    .opacity(0.35)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.black, Color.yellow)
            }
        } else if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        } else {
            Image(nsImage: ThumbnailCache.shared.genericIcon(forPathExtension: item.pathExtension))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .opacity(0.6)
        }
    }
}

struct ShelfHeaderActions: View {
    @EnvironmentObject private var shelf: ShelfStore

    var body: some View {
        if !shelf.items.isEmpty {
            Text(shelf.selection.isEmpty ? "\(shelf.items.count)" : "\(shelf.selection.count)/\(shelf.items.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.5))
            HeaderIconButton(systemImage: "trash.fill", help: "Alle leeren") {
                shelf.removeAll()
            }
        }
    }
}
