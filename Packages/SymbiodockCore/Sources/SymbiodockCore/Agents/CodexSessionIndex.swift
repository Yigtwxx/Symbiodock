import Foundation

/// Reads `~/.codex/session_index.jsonl`: the names Codex gave its threads.
public enum CodexSessionIndex {
    /// Thread id → name. A thread listed more than once keeps its last name.
    public static func titles(from data: Data) -> [String: String] {
        var titles: [String: String] = [:]
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = object["id"] as? String, !id.isEmpty,
                  let name = object["thread_name"] as? String, !name.isEmpty
            else { continue }
            titles[id] = name
        }
        return titles
    }
}
