import SwiftUI
import SymbiodockCore

/// A panel at the right of the shelf: the selected files, what they are, and the formats
/// they can become, one chip each, in the colour of the kind the chip makes.
struct FileActionsColumn: View {
    static let width: CGFloat = 168

    /// The selection in shelf order; never empty.
    let items: [ShelfItem]
    /// The stack when the selection is exactly one whole stack of two or more: it can be spread.
    let stackID: UUID?
    let previews: FilePreviews?
    let conversions: [UUID: FileConversion]
    let notice: ShelfNotice?
    let onRequest: (FileRequest) -> Void

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    private var ids: [UUID] { items.map(\.id) }

    /// Its corners follow the island's, which lies `FilesContent.margin` further out.
    private static let radius = IslandLayout.expandedCornerRadius - FilesContent.margin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
            infoLine
            let converting = ids.filter { conversions[$0] != nil }
            if converting.isEmpty {
                chips
            } else {
                progress(labels: converting.compactMap { conversions[$0]?.label }, ids: converting)
            }
        }
        .padding(8)
        .frame(width: Self.width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
    }

    private var title: String {
        items.count == 1 ? items[0].name : "\(items.count) files"
    }

    private var titleRow: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            iconButton("folder", label: "Show in Finder") { onRequest(.reveal(ids)) }
            if let stackID {
                iconButton("square.stack.3d.up.slash", label: "Unstack") { onRequest(.unstack(stackID)) }
            }
            iconButton("xmark", label: "Remove") { onRequest(.remove(ids)) }
        }
        .frame(height: 20)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .background(.white.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel(label)
    }

    /// A notice about a selected file takes the place of the details until the person moves on.
    @ViewBuilder
    private var infoLine: some View {
        if let notice, ids.contains(notice.id) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(red: 1, green: 69.0 / 255, blue: 58.0 / 255))
                Text(notice.text).foregroundStyle(.white.opacity(0.7))
            }
            .font(.system(size: 10))
            .lineLimit(1)
        } else {
            HStack(spacing: 5) {
                KindDots(kinds: kinds)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    /// The kinds of the selection in the order they first appear.
    private var kinds: [FileKind] {
        var kinds: [FileKind] = []
        for item in items where !kinds.contains(item.kind) { kinds.append(item.kind) }
        return kinds
    }

    /// "1.2 MB · Document" for one file. For several, their total size once every size is
    /// known, else what they are: "2 documents, 1 other".
    private var detail: String {
        let sizes = items.map { previews?.size(for: $0) }
        if items.count == 1 {
            let size = sizes[0].map { Self.format($0) }
            return [size, FileKindPalette.name(items[0].kind)].compactMap { $0 }.joined(separator: " · ")
        }
        if sizes.allSatisfy({ $0 != nil }) {
            return Self.format(sizes.reduce(0) { $0 + ($1 ?? 0) })
        }
        return kinds.map { kind in
            FileKindPalette.count(items.filter { $0.kind == kind }.count, of: kind)
        }.joined(separator: ", ")
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @ViewBuilder
    private var chips: some View {
        let labels = ConversionCatalog.commonLabels(items)
        if !labels.isEmpty {
            Text("CONVERT TO")
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 4)
                .padding(.bottom, 3)
            LazyVGrid(columns: Self.columns, spacing: 4) {
                ForEach(labels, id: \.self) { label in
                    Button(label) { onRequest(.convert(ids, label: label)) }
                        .buttonStyle(ChipStyle(color: FileKindPalette.color(made(by: label))))
                }
            }
        }
    }

    /// The kind of file a chip makes, found through the target one of the selected files has
    /// for it: `PDF` makes a PDF, `PNG` an image, `ZIP` an archive, `Unzip` a folder.
    private func made(by label: String) -> FileKind {
        for item in items {
            let targets = ConversionCatalog.targets(
                pathExtension: item.url.pathExtension, isDirectory: item.isDirectory)
            guard let target = targets.first(where: { $0.label == label }) else { continue }
            return target.pathExtension.isEmpty
                ? .folder : FileKind.of(pathExtension: target.pathExtension, isDirectory: false)
        }
        return .other
    }

    /// In the chips' place while selected files convert; `ids` are those files, until each is
    /// an ordinary tile again, and `labels` what each becomes.
    @ViewBuilder
    private func progress(labels: [String], ids: [UUID]) -> some View {
        Text(ConversionBatch.progressText(labels: labels))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            // A two-digit count with a long label can be a little wider than the panel.
            .minimumScaleFactor(0.85)
            .padding(.top, 10)
            .padding(.bottom, 6)
        Button("Cancel") { onRequest(.cancel(ids)) }
            .buttonStyle(ChipStyle(color: .white))
            .frame(width: 64)
    }
}

/// Up to three overlapping dots in the colours of the selected kinds.
private struct KindDots: View {
    let kinds: [FileKind]

    var body: some View {
        HStack(spacing: -2.5) {
            ForEach(kinds.prefix(3), id: \.self) { kind in
                Circle()
                    .fill(FileKindPalette.color(kind))
                    .frame(width: 6, height: 6)
                    .overlay { Circle().stroke(.black.opacity(0.6), lineWidth: 1) }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A chip tinted in the colour of what it makes; it dims while pressed, so a click is felt.
private struct ChipStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .background(color.opacity(0.16), in: shape)
            .overlay { shape.strokeBorder(color.opacity(0.3), lineWidth: 0.5) }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A round icon button: pale glyph, brighter while pressed.
private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.9 : 0.6))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
