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

    /// Returns nil when the line says nothing is playing. Throws on a malformed line.
    public static func info(fromStreamLine line: String) throws -> NowPlayingInfo? {
        let payload = try JSONDecoder().decode(Envelope.self, from: Data(line.utf8)).payload
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
