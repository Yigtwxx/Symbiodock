import SwiftUI
import SymbiodockCore

/// The System tab: how busy and how warm this Mac is, and how fast its network. Three
/// columns: the measures with their bars, the network panel, the devices panel.
///
/// The texts and the graph change only when a new sample arrives (every two seconds); the
/// bars move in Core Animation. Nothing here redraws by itself.
struct SystemContent: View {
    let snapshot: SystemSnapshot?
    let history: NetworkHistory
    var devices: [LANDevice] = []
    var scan: LANScanState = .idle
    var canScan = false
    /// The header band's height; the page starts below it.
    let topInset: CGFloat
    /// `Scan` was pressed.
    var onScan: () -> Void = {}

    private static let topGap: CGFloat = 2
    private static let sideMargin: CGFloat = 16
    private static let bottomMargin: CGFloat = 14
    private static let columnGap: CGFloat = 10
    private static let networkWidth: CGFloat = 128
    private static let devicesWidth: CGFloat = 164

    var body: some View {
        HStack(spacing: Self.columnGap) {
            meters
            NetworkPanel(snapshot: snapshot, history: history)
                .frame(width: Self.networkWidth)
            DevicesPanel(devices: devices, scan: scan, canScan: canScan, onScan: onScan)
                .frame(width: Self.devicesWidth)
        }
        .padding(.top, topInset + Self.topGap)
        .padding(.horizontal, Self.sideMargin)
        .padding(.bottom, Self.bottomMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var meters: some View {
        VStack(spacing: 0) {
            MeterRow(title: "CPU", fraction: snapshot?.cpu, colors: SystemPalette.cpu) {
                temperature(snapshot?.temperatures.cpu)
                value(SystemLabels.percent(snapshot?.cpu))
            }
            .accessibilityValue(spoken(snapshot?.cpu, snapshot?.temperatures.cpu))
            Spacer(minLength: 0)
            MeterRow(title: "GPU", fraction: snapshot?.gpu, colors: SystemPalette.gpu) {
                temperature(snapshot?.temperatures.gpu)
                value(SystemLabels.percent(snapshot?.gpu))
            }
            .accessibilityValue(spoken(snapshot?.gpu, snapshot?.temperatures.gpu))
            Spacer(minLength: 0)
            MeterRow(title: "RAM", fraction: snapshot?.memory?.fraction, colors: SystemPalette.ram) {
                memory(snapshot?.memory)
            }
            .accessibilityValue(spokenMemory(snapshot?.memory))
        }
        .padding(.vertical, 7)
        .padding(.leading, 2)
        .padding(.trailing, 4)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(minWidth: 36, alignment: .trailing)
    }

    private func temperature(_ celsius: Double?) -> some View {
        Text(SystemLabels.degrees(celsius))
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(SystemPalette.color(for: SystemLabels.tier(celsius)))
    }

    @ViewBuilder
    private func memory(_ use: MemoryUse?) -> some View {
        if let use {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(SystemLabels.gigabytes(use.used))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text("/ \(SystemLabels.wholeGigabytes(use.total)) GB")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        } else {
            value(SystemLabels.missing)
        }
    }

    private func spoken(_ fraction: Double?, _ celsius: Double?) -> String {
        guard let fraction else { return "Unknown" }
        // The same number the row shows; VoiceOver reads "31%" as "31 percent".
        let percent = SystemLabels.percent(fraction)
        guard let celsius else { return percent }
        return "\(percent), \(Int(celsius.rounded())) degrees"
    }

    private func spokenMemory(_ use: MemoryUse?) -> String {
        guard let use else { return "Unknown" }
        return "\(SystemLabels.gigabytes(use.used)) of \(SystemLabels.wholeGigabytes(use.total)) gigabytes"
    }
}

/// One measure: its name, what it reads, and a bar under them.
private struct MeterRow<Trailing: View>: View {
    let title: String
    let fraction: Double?
    let colors: [NSColor]
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 0)
                trailing()
            }
            MeterBar(fraction: fraction, colors: colors)
                .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// The small caption at the top of a panel.
private struct PanelCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.35))
    }
}

private extension View {
    /// The faint rounded box a panel sits in.
    func systemPanel() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Download and upload speed, and the last minute of both.
private struct NetworkPanel: View {
    let snapshot: SystemSnapshot?
    let history: NetworkHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelCaption("NETWORK")
            if snapshot?.isOnline == false {
                Text("Offline")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 6)
            } else {
                rate(snapshot?.network?.down, title: "Download", pointsDown: true, color: SystemPalette.down)
                    .padding(.top, 6)
                rate(snapshot?.network?.up, title: "Upload", pointsDown: false, color: SystemPalette.up)
                    .padding(.top, 3)
            }
            Spacer(minLength: 4)
            NetworkGraph(history: history)
                .frame(height: 34)
        }
        .systemPanel()
    }

    /// One direction's speed. VoiceOver hears the direction and the speed: the arrow says
    /// nothing to it.
    private func rate(_ bytesPerSecond: Double?, title: String, pointsDown: Bool, color: Color) -> some View {
        HStack(spacing: 5) {
            RateArrow(pointsDown: pointsDown)
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: 9, height: 9)
            Text(bytesPerSecond.map(SystemLabels.rate) ?? SystemLabels.missing)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(bytesPerSecond.map(SystemLabels.rate) ?? "Unknown")
    }
}

/// An arrow on a 9-point square: a shaft and a head.
private struct RateArrow: Shape {
    let pointsDown: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tip: CGFloat = pointsDown ? 7.7 : 1.3
        let tail: CGFloat = pointsDown ? 1.5 : 7.5
        let barbs: CGFloat = pointsDown ? 5 : 4
        path.move(to: CGPoint(x: 4.5, y: tail))
        path.addLine(to: CGPoint(x: 4.5, y: tip))
        path.move(to: CGPoint(x: 1.8, y: barbs))
        path.addLine(to: CGPoint(x: 4.5, y: tip))
        path.addLine(to: CGPoint(x: 7.2, y: barbs))
        return path.applying(CGAffineTransform(scaleX: rect.width / 9, y: rect.height / 9))
    }
}

/// The last minute: download as a filled line, upload as a thin one, on one scale.
private struct NetworkGraph: View {
    let history: NetworkHistory

    var body: some View {
        ZStack {
            GraphLine(values: history.downFractions, closes: true)
                .fill(
                    LinearGradient(
                        colors: [SystemPalette.down.opacity(0.5), SystemPalette.downFade.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
            GraphLine(values: history.upFractions)
                .stroke(
                    SystemPalette.up.opacity(0.9),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            GraphLine(values: history.downFractions)
                .stroke(
                    SystemPalette.down, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// A line through samples, the newest at the right edge. A sample always takes the same
/// width, so a graph that is not full yet grows in from the right.
private struct GraphLine: Shape {
    /// 0...1 each.
    let values: [Double]
    /// Whether the line is closed along the bottom, to be filled.
    var closes = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let inset: CGFloat = 2
        let step = rect.width / CGFloat(NetworkHistory.capacity - 1)
        let points = values.enumerated().map { index, value in
            CGPoint(
                x: rect.maxX - step * CGFloat(values.count - 1 - index),
                y: rect.maxY - inset - (rect.height - 2 * inset) * CGFloat(min(1, max(0, value))))
        }
        path.addLines(points)
        if closes, let first = points.first {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// The devices on the network: those the Mac already knows, and after `Scan` everything that
/// answered. The list changes only when a new one arrives.
private struct DevicesPanel: View {
    let devices: [LANDevice]
    let scan: LANScanState
    let canScan: Bool
    let onScan: () -> Void

    private static let rowHeight: CGFloat = 20
    /// More rows than this are scrolled, and the list fades out at its lower edge.
    private static let visibleRows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                PanelCaption("DEVICES")
                if !devices.isEmpty { count }
                Spacer(minLength: 0)
                if canScan { scanButton }
            }
            .frame(height: 16)
            if devices.isEmpty {
                Spacer(minLength: 0)
                Text(SystemLabels.missing)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("No devices known")
                Spacer(minLength: 0)
            } else {
                list.padding(.top, 3)
            }
            if scan == .blocked {
                Text("Local Network access needed")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
            }
        }
        .systemPanel()
    }

    private var count: some View {
        Text("\(devices.count)")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel(LANLabels.count(devices.count))
    }

    private var scanButton: some View {
        Button(action: onScan) {
            Text(scan == .scanning ? "Scanning…" : "Scan")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(scan == .scanning ? 0.4 : 0.85))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(scan == .scanning)
        .accessibilityHint("Looks for every device on this network")
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(devices) { device in
                    row(device)
                }
            }
        }
        .mask {
            // Fading out at the lower edge says that the list goes on.
            if devices.count > Self.visibleRows {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.62),
                        .init(color: .black.opacity(0.12), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            } else {
                Rectangle()
            }
        }
    }

    private func row(_ device: LANDevice) -> some View {
        HStack(spacing: 6) {
            dot(device.kind)
                .frame(width: 5, height: 5)
            Text(device.title)
                .font(.system(size: 11, weight: device.isNamed ? .medium : .regular).monospacedDigit())
                .foregroundStyle(.white.opacity(device.isNamed ? 1 : 0.55))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if device.isNamed {
                // The end of the address tells two devices of the same name apart.
                Text(device.address.suffix)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.38))
            }
        }
        .frame(height: Self.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.title)
        .accessibilityValue(device.address.text)
    }

    @ViewBuilder
    private func dot(_ kind: LANDevice.Kind) -> some View {
        switch kind {
        case .router: Circle().strokeBorder(SystemPalette.down, lineWidth: 1.2)
        case .thisMac: Circle().fill(.white)
        case .other: Circle().fill(.white.opacity(0.35))
        }
    }
}
