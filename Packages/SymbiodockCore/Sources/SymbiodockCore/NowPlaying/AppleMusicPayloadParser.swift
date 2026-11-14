import Foundation

/// Parses the reply of the Music state script: six fields separated by the ASCII unit
/// separator (U+001F) — name, artist, album, duration, player position, player state —
/// or the word "stopped". A unit separator cannot appear in a track name, a newline can.
public enum AppleMusicPayloadParser {
    public static func info(fromScriptOutput output: String, at now: Date) -> NowPlayingInfo? {
        // A field Music has no value for arrives as the literal text "missing value".
        let lines = output.split(separator: "\u{1F}", omittingEmptySubsequences: false)
            .map { $0 == "missing value" ? "" : String($0) }
        guard lines.count == 6, !lines[0].isEmpty else { return nil }

        return NowPlayingInfo(
            title: lines[0],
            artist: lines[1],
            album: lines[2].isEmpty ? nil : lines[2],
            duration: number(lines[3]).flatMap { $0 > 0 ? $0 : nil },
            elapsed: number(lines[4]),
            elapsedAt: now,
            isPlaying: lines[5] == "playing",
            sourceName: "Music")
    }

    /// AppleScript writes numbers with the user's decimal separator, and large ones as `1.002E+4`.
    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}
