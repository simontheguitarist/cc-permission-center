import Foundation

/// Reads recent assistant text from a Claude Code transcript (JSONL).
enum TranscriptReader {
    /// Returns the assistant's final text in its most recent message,
    /// or nil if the most recent message contains no text (i.e. only tool
    /// uses, meaning the assistant is mid-turn, not asking the user).
    static func lastAssistantText(transcriptPath: String) -> String? {
        guard !transcriptPath.isEmpty,
              FileManager.default.fileExists(atPath: transcriptPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: transcriptPath))
        else { return nil }

        // Read up to the last 16 MB. Claude transcripts can have very large
        // assistant entries (thinking blocks alone are often 50KB+), so we
        // need a generous tail to reach the most recent visible text.
        let tailBytes = 16 * 1024 * 1024
        let slice = data.suffix(tailBytes)
        guard let text = String(data: slice, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)

        // Walk backwards looking for the most recent assistant text. Keep
        // walking past tool-use-only assistant messages — Claude may emit
        // text, then tool_use(s) as separate JSONL entries; we want the
        // most recent *text* the user actually saw before the turn ended.
        NSLog("CCPC reader: tail=\(slice.count) bytes, \(lines.count) lines")
        var walked = 0
        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            walked += 1
            let type = obj["type"] as? String ?? ""
            let timestamp = obj["timestamp"] as? String ?? ""

            let contentValue: Any?
            if let message = obj["message"] as? [String: Any] {
                contentValue = message["content"]
            } else {
                contentValue = obj["content"]
            }
            let blockTypes: String = {
                if let blocks = contentValue as? [[String: Any]] {
                    return blocks.map { ($0["type"] as? String) ?? "?" }.joined(separator: ",")
                }
                if contentValue is String { return "string" }
                return "?"
            }()
            NSLog("CCPC reader[#\(walked)] type=\(type) ts=\(timestamp.suffix(15)) blocks=[\(blockTypes)]")

            if type == "user" {
                if let blocks = contentValue as? [[String: Any]],
                   blocks.allSatisfy({ ($0["type"] as? String) == "tool_result" }) {
                    continue
                }
                NSLog("CCPC reader: stopping at user message")
                return nil
            }
            guard type == "assistant" else { continue }

            if let direct = contentValue as? String {
                let t = direct.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
                continue
            }
            guard let blocks = contentValue as? [[String: Any]] else { continue }

            var latest: String?
            for block in blocks where (block["type"] as? String) == "text" {
                if let raw = block["text"] as? String {
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { latest = trimmed }
                }
            }
            if let latest {
                NSLog("CCPC reader: returning text from walk #\(walked): \(latest.prefix(120))")
                return latest
            }
        }
        NSLog("CCPC reader: walked \(walked) entries, no text found")
        return nil
    }
}
