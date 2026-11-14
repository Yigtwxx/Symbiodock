import Foundation

/// Parses one line of `mediaremote-adapter.pl ... stream --no-diff` output.
public enum MediaRemotePayloadParser {
    private struct Envelope: Decodable {
        let payload: Payload
    }

    /// Every field is optional and decoded leniently: a value of an unexpected type counts as
    /// absent, so one odd field does not drop the whole update.
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

        private enum CodingKeys: String, CodingKey {
            case title, artist, album, duration, elapsedTime, timestamp, playing
            case bundleIdentifier, parentApplicationBundleIdentifier, artworkData
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try? c.decodeIfPresent(String.self, forKey: .title)
            artist = try? c.decodeIfPresent(String.self, forKey: .artist)
            album = try? c.decodeIfPresent(String.self, forKey: .album)
            duration = try? c.decodeIfPresent(Double.self, forKey: .duration)
            elapsedTime = try? c.decodeIfPresent(Double.self, forKey: .elapsedTime)
            timestamp = try? c.decodeIfPresent(String.self, forKey: .timestamp)
            bundleIdentifier = try? c.decodeIfPresent(String.self, forKey: .bundleIdentifier)
            parentApplicationBundleIdentifier =
                try? c.decodeIfPresent(String.self, forKey: .parentApplicationBundleIdentifier)
            artworkData = try? c.decodeIfPresent(String.self, forKey: .artworkData)
            if let flag = try? c.decodeIfPresent(Bool.self, forKey: .playing) {
                playing = flag
            } else if let number = try? c.decodeIfPresent(Int.self, forKey: .playing),
                      number == 0 || number == 1 {
                playing = number == 1
            } else {
                playing = nil
            }
        }
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
