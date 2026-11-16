import SwiftUI
import SymbiodockCore

/// The selected file: its name, what it is, and the formats it can become.
struct FileActionsColumn: View {
    static let width: CGFloat = 168

    let item: ShelfItem
    let detail: String?
    let conversion: FileConversion?
    let notice: ShelfNotice?
    let onRequest: (FileRequest) -> Void

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            nameRow
            infoLine
            if let conversion {
                converting(conversion)
            } else {
                Text("Convert to")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 2)
                LazyVGrid(columns: Self.columns, spacing: 4) {
                    ForEach(targets) { target in
                        Button(target.label) { onRequest(.convert([item.id], label: target.label)) }
                            .buttonStyle(ChipStyle())
                    }
                }
            }
        }
        .frame(width: Self.width, alignment: .topLeading)
    }

    private var targets: [ConversionTarget] {
        ConversionCatalog.targets(pathExtension: item.url.pathExtension, isDirectory: item.isDirectory)
    }

    private var nameRow: some View {
        HStack(spacing: 4) {
            Text(item.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            iconButton("folder", label: "Show in Finder") { onRequest(.reveal([item.id])) }
            iconButton("xmark", label: "Remove") { onRequest(.remove([item.id])) }
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// A notice about this file takes the place of its details until the person moves on.
    @ViewBuilder
    private var infoLine: some View {
        if let notice, notice.id == item.id {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(red: 1, green: 69.0 / 255, blue: 58.0 / 255))
                Text(notice.text).foregroundStyle(.white.opacity(0.7))
            }
            .font(.system(size: 10))
            .lineLimit(1)
        } else {
            Text([detail, FileKindPalette.name(item.kind)].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func converting(_ conversion: FileConversion) -> some View {
        Text("Converting to \(conversion.label)…")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .padding(.top, 2)
        Button("Cancel") { onRequest(.cancel([item.id])) }
            .buttonStyle(ChipStyle())
            .frame(width: 56)
    }
}

/// A format chip: a pale capsule that dims while it is pressed, so a click is felt.
private struct ChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .background(.white.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
