import Foundation

/// Parses one line of `mediaremote-adapter.pl ... stream-clients` (or `get-clients`) output:
/// a JSON array with one object per app the system knows plays something.
public enum NowPlayingClientsParser {
    /// One object of the array: the keys of a `stream` payload, plus who the app is.
    private struct Entry: Decodable {
        let payload: MediaRemotePayloadParser.Payload
        let pid: Int32?
        let isElected: Bool

        private enum CodingKeys: String, CodingKey {
            case processIdentifier, elected
        }

        init(from decoder: any Decoder) throws {
            payload = try MediaRemotePayloadParser.Payload(from: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pid = try? c.decodeIfPresent(Int32.self, forKey: .processIdentifier)
            isElected = (try? c.decodeIfPresent(Bool.self, forKey: .elected)) ?? false
        }
    }

    /// Keeps one bad entry from dropping the whole line.
    private struct LenientEntry: Decodable {
        let entry: Entry?

        init(from decoder: any Decoder) throws {
            entry = try? Entry(from: decoder)
        }
    }

    /// Convenience for text input; forwards to the `Data` entry point.
    public static func clients(fromStreamLine line: String) -> [NowPlayingClient] {
        clients(fromStreamLine: Data(line.utf8))
    }

    /// The apps in the helper's order. A malformed line gives none; an entry without a title
    /// or a process identifier (commands are sent by it) is left out.
    /// Takes bytes because the helper writes U+2028 and friends unescaped in titles.
    public static func clients(fromStreamLine line: Data) -> [NowPlayingClient] {
        guard let entries = try? JSONDecoder().decode([LenientEntry].self, from: line) else {
            return []
        }
        return entries.compactMap { lenient in
            guard let entry = lenient.entry, let pid = entry.pid, pid > 0,
                  let info = MediaRemotePayloadParser.info(from: entry.payload)
            else { return nil }
            return NowPlayingClient(pid: pid, isElected: entry.isElected, info: info)
        }
    }
}
