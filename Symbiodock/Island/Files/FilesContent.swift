import SwiftUI

/// The Files tab. For now only the idle state; the shelf comes into it later.
struct FilesContent: View {
    /// Height of the header band; nothing can be shown behind it.
    let topInset: CGFloat

    var body: some View {
        idle
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, topInset)
    }

    private var idle: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
            Text("Drop files here")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}
