import Foundation

/// Parses the reply of the Music state script: six lines —
/// name, artist, album, duration, player position, player state — or the word "stopped".
public enum AppleMusicPayloadParser {
    public static func info(fromScriptOutput output: String, at now: Date) -> NowPlayingInfo? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
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

    /// AppleScript writes numbers with the user's decimal separator.
    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}
