import Foundation

/// Finds the question a Claude Code session is waiting on, in the end of its transcript.
public enum ClaudeTranscriptPromptReader {
    /// How much of the transcript's end is worth reading.
    public static let tailSize = 256 * 1024
    private static let maximumLength = 300
    private static let toolUseMarker = Data("\"tool_use\"".utf8)
    private static let toolResultMarker = Data("\"tool_result\"".utf8)

    /// The text of the last `AskUserQuestion` that has neither a result nor a later tool
    /// call after it. Lines that are cut off or are not JSON are skipped.
    public static func pendingQuestion(inTail data: Data) -> String? {
        var pending: (id: String, question: String)?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            // Most lines are neither; do not parse them.
            guard line.range(of: toolUseMarker) != nil || line.range(of: toolResultMarker) != nil,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { continue }
            for item in content {
                switch item["type"] as? String {
                case "tool_use":
                    pending = question(in: item)
                case "tool_result":
                    if let id = item["tool_use_id"] as? String, id == pending?.id { pending = nil }
                default:
                    break
                }
            }
        }
        return pending?.question
    }

    /// The question of an `AskUserQuestion` call; nil for any other tool call.
    private static func question(in toolUse: [String: Any]) -> (id: String, question: String)? {
        guard toolUse["name"] as? String == "AskUserQuestion",
              let id = toolUse["id"] as? String,
              let input = toolUse["input"] as? [String: Any],
              let questions = input["questions"] as? [[String: Any]],
              let text = questions.first?["question"] as? String
        else { return nil }
        let oneLine = text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !oneLine.isEmpty else { return nil }
        return (id, String(oneLine.prefix(maximumLength)))
    }
}
