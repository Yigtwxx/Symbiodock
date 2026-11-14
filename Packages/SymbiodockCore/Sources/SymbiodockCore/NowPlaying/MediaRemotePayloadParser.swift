import Foundation

/// Parses one line of `mediaremote-adapter.pl ... stream --no-diff` output.
public enum MediaRemotePayloadParser {
    private struct Envelope: Decodable {
        let payload: Payload
    }

    private struct Payload: Decodable {
        let title: String?
        let artist: String?
        let album: String?
        let duration: Double?
        let elapsedTime: Double?
        let timestamp: String?
        let playing: Bool?
        let bundleIdentifier: String?
        let parentApplicationBundleIdentifier: String?
        let artworkData: String?
    }

    /// Convenience for text input; forwards to the `Data` entry point.
    public static func info(fromStreamLine line: String) throws -> NowPlayingInfo? {
        try info(fromStreamLine: Data(line.utf8))
    }

    /// Returns nil when the line says nothing is playing. Throws on a malformed line.
    /// Takes bytes because the helper writes U+2028 and friends unescaped in titles.
    public static func info(fromStreamLine line: Data) throws -> NowPlayingInfo? {
        let payload = try JSONDecoder().decode(Envelope.self, from: line).payload
        guard let title = payload.title, !title.isEmpty else { return nil }

        let duration = payload.duration.flatMap { value in
            value > 0 && value < NowPlayingInfo.maximumPlausibleDuration ? value : nil
        }
        // A browser reports its GPU helper as the player; the parent is the app the user knows.
        let identifier = payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier ?? ""

        return NowPlayingInfo(
            title: title,
            artist: payload.artist ?? "",
            album: payload.album.flatMap { $0.isEmpty ? nil : $0 },
            artworkData: payload.artworkData.flatMap { Data(base64Encoded: $0) },
            duration: duration,
            elapsed: payload.elapsedTime,
            elapsedAt: payload.timestamp.flatMap { try? Date($0, strategy: .iso8601) },
            isPlaying: payload.playing ?? false,
            sourceName: SourceName.displayName(forBundleIdentifier: identifier))
    }
}
