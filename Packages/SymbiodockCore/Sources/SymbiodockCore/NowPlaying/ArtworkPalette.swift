import Foundation

/// A colour in sRGB, each part 0...1.
public struct TintColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// The colours a cover lends to the bars beside it: one, or a run of up to three.
public struct ArtworkTint: Equatable, Sendable {
    /// One to three colours, in the order the run passes through them.
    public let stops: [TintColor]

    public init(stops: [TintColor]) {
        self.stops = stops
    }

    /// The colour at `position` (0...1) along the run.
    public func color(at position: Double) -> TintColor {
        guard let first = stops.first else { return TintColor(red: 1, green: 1, blue: 1) }
        guard stops.count > 1 else { return first }
        let scaled = min(max(position, 0), 1) * Double(stops.count - 1)
        let index = min(Int(scaled), stops.count - 2)
        let fraction = scaled - Double(index)
        let (a, b) = (stops[index], stops[index + 1])
        return TintColor(
            red: a.red + (b.red - a.red) * fraction,
            green: a.green + (b.green - a.green) * fraction,
            blue: a.blue + (b.blue - a.blue) * fraction)
    }
}

/// Picks the colours of a cover from a small copy of it.
public enum ArtworkPalette {
    /// The side of the copy the app hands over; more pixels would not change the answer.
    public static let sampleSide = 32
    /// How bright a colour must at least be to read on the black island (relative luminance;
    /// about 4.6 : 1 against black).
    public static let minimumLuminance = 0.18

    private static let binCount = 24
    /// Greyer or darker than this, a pixel has no colour to speak of.
    private static let minimumSaturation = 0.2
    private static let minimumValue = 0.2
    /// The share of a wholly vivid cover that the coloured pixels must add up to.
    private static let minimumVividness = 0.02
    /// The share of the cover's colour a hue needs to be one of its colours.
    private static let minimumShare = 0.15
    /// Hues closer than this many bins (15° each) are one colour. Red, pink and purple are
    /// about 40° apart, and a cover that runs through them should give all three.
    private static let minimumDistance = 2
    private static let maximumStops = 3

    private struct Bin {
        var weight = 0.0
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var x = 0.0

        static func + (a: Bin, b: Bin) -> Bin {
            Bin(
                weight: a.weight + b.weight, red: a.red + b.red, green: a.green + b.green,
                blue: a.blue + b.blue, x: a.x + b.x)
        }
    }

    /// `pixels` row by row, `width` to a row. Nil for a cover without colour (or no cover):
    /// the bars then stay white.
    public static func tint(pixels: [TintColor], width: Int) -> ArtworkTint? {
        guard width > 0, !pixels.isEmpty, pixels.count % width == 0 else { return nil }
        var bins = [Bin](repeating: Bin(), count: binCount)
        for (index, pixel) in pixels.enumerated() {
            let (hue, saturation, value) = hsv(of: pixel)
            guard saturation >= minimumSaturation, value >= minimumValue else { continue }
            let weight = saturation * value
            let bin = min(Int(hue * Double(binCount)), binCount - 1)
            bins[bin].weight += weight
            bins[bin].red += pixel.red * weight
            bins[bin].green += pixel.green * weight
            bins[bin].blue += pixel.blue * weight
            bins[bin].x += (Double(index % width) + 0.5) / Double(width) * weight
        }
        let total = bins.reduce(0) { $0 + $1.weight }
        guard total / Double(pixels.count) >= minimumVividness else { return nil }

        // The strongest hues that are far enough apart, each with its two neighbours.
        var chosen: [Int] = []
        for bin in bins.indices.sorted(by: { bins[$0].weight > bins[$1].weight }) {
            guard chosen.count < maximumStops else { break }
            guard chosen.allSatisfy({ distance($0, bin) >= minimumDistance }) else { continue }
            guard cluster(around: bin, in: bins).weight >= minimumShare * total else { continue }
            chosen.append(bin)
        }
        guard !chosen.isEmpty else { return nil }

        // Round the wheel, starting after the widest gap, so that the run passes through
        // neighbouring hues; then turned so that it starts with the colour on the cover's left.
        var ordered = chosen.sorted()
        if ordered.count > 1 {
            let gaps = ordered.indices.map { index in
                (ordered[(index + 1) % ordered.count] - ordered[index] + binCount) % binCount
            }
            let widest = gaps.indices.max { gaps[$0] < gaps[$1] } ?? 0
            let start = (widest + 1) % ordered.count
            ordered = Array(ordered[start...] + ordered[..<start])
        }
        var clusters = ordered.map { cluster(around: $0, in: bins) }
        if let first = clusters.first, let last = clusters.last,
           first.x / first.weight > last.x / last.weight {
            clusters.reverse()
        }
        return ArtworkTint(
            stops: clusters.map { cluster in
                readable(
                    TintColor(
                        red: cluster.red / cluster.weight, green: cluster.green / cluster.weight,
                        blue: cluster.blue / cluster.weight))
            })
    }

    private static func distance(_ a: Int, _ b: Int) -> Int {
        let direct = abs(a - b)
        return min(direct, binCount - direct)
    }

    private static func cluster(around bin: Int, in bins: [Bin]) -> Bin {
        bins[(bin + binCount - 1) % binCount] + bins[bin] + bins[(bin + 1) % binCount]
    }

    /// The colour at full strength, and mixed with white as far as it takes to read on black.
    static func readable(_ color: TintColor) -> TintColor {
        let (hue, saturation, value) = hsv(of: color)
        let bright = Self.color(hue: hue, saturation: saturation, value: max(value, 0.92))
        let luminance = luminance(of: bright)
        guard luminance < minimumLuminance else { return bright }
        let mix = (minimumLuminance - luminance) / (1 - luminance)
        func lift(_ part: Double) -> Double { encoded(linear(part) + (1 - linear(part)) * mix) }
        return TintColor(red: lift(bright.red), green: lift(bright.green), blue: lift(bright.blue))
    }

    /// Relative luminance, 0 (black) to 1 (white).
    public static func luminance(of color: TintColor) -> Double {
        0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// The hue of a colour, 0..<1 round the wheel; 0 for a grey.
    public static func hue(of color: TintColor) -> Double {
        hsv(of: color).hue
    }

    /// `hue` 0...1 round the wheel (1 is 0 again).
    public static func color(hue: Double, saturation: Double, value: Double) -> TintColor {
        let turn = (hue - hue.rounded(.down)) * 6
        let sector = Int(turn) % 6
        let fraction = turn - Double(Int(turn))
        let low = value * (1 - saturation)
        let falling = value * (1 - saturation * fraction)
        let rising = value * (1 - saturation * (1 - fraction))
        switch sector {
        case 0: return TintColor(red: value, green: rising, blue: low)
        case 1: return TintColor(red: falling, green: value, blue: low)
        case 2: return TintColor(red: low, green: value, blue: rising)
        case 3: return TintColor(red: low, green: falling, blue: value)
        case 4: return TintColor(red: rising, green: low, blue: value)
        default: return TintColor(red: value, green: low, blue: falling)
        }
    }

    private static func hsv(of color: TintColor) -> (hue: Double, saturation: Double, value: Double) {
        let high = max(color.red, color.green, color.blue)
        let low = min(color.red, color.green, color.blue)
        let range = high - low
        guard high > 0, range > 0 else { return (0, 0, high) }
        var hue: Double
        if high == color.red {
            hue = (color.green - color.blue) / range
        } else if high == color.green {
            hue = 2 + (color.blue - color.red) / range
        } else {
            hue = 4 + (color.red - color.green) / range
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        if hue >= 1 { hue -= 1 }
        return (hue, range / high, high)
    }

    private static func linear(_ part: Double) -> Double {
        part <= 0.04045 ? part / 12.92 : pow((part + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ part: Double) -> Double {
        part <= 0.0031308 ? part * 12.92 : 1.055 * pow(part, 1 / 2.4) - 0.055
    }
}
