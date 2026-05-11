import Foundation

/// Tracks active Claude Code sessions so the popup can disambiguate when
/// multiple sessions share the same project directory.
@MainActor
final class SessionRegistry {
    struct Entry {
        let sessionId: String
        let cwd: String
        let terminal: TerminalInfo?
        var lastSeen: Date
    }

    private var entries: [String: Entry] = [:]
    private let freshnessWindow: TimeInterval = 60 * 60  // 1 hour

    /// Records that we saw activity from this session.
    func touch(sessionId: String, cwd: String, terminal: TerminalInfo?) {
        entries[sessionId] = Entry(
            sessionId: sessionId,
            cwd: cwd,
            terminal: terminal,
            lastSeen: Date()
        )
        pruneStale()
    }

    /// Display label for a session: cwd basename, plus terminal disambiguator
    /// if any other active session lives in the same cwd.
    func projectLabel(sessionId: String, cwd: String, terminal: TerminalInfo?) -> (label: String, terminalLine: String?) {
        let basename = (cwd as NSString).lastPathComponent
        let project = basename.isEmpty ? cwd : basename

        let cutoff = Date().addingTimeInterval(-freshnessWindow)
        let siblings = entries.values.filter {
            $0.sessionId != sessionId &&
            $0.cwd == cwd &&
            $0.lastSeen >= cutoff
        }

        if siblings.isEmpty {
            return (project, nil)
        }

        return (project, terminalLine(terminal: terminal, sessionId: sessionId))
    }

    private func terminalLine(terminal: TerminalInfo?, sessionId: String) -> String {
        let app = terminal?.displayName ?? "terminal"
        let suffix = shortIdentifier(terminal: terminal, sessionId: sessionId)
        return "\(app) · \(suffix)"
    }

    private func shortIdentifier(terminal: TerminalInfo?, sessionId: String) -> String {
        if let it = terminal?.itermSessionId, !it.isEmpty {
            // iTerm session IDs look like "w0t1p0:UUID"; the tail UUID is more useful
            let trimmed = it.split(separator: ":").last.map(String.init) ?? it
            return String(trimmed.prefix(6))
        }
        return String(sessionId.prefix(6))
    }

    private func pruneStale() {
        let cutoff = Date().addingTimeInterval(-freshnessWindow)
        entries = entries.filter { $0.value.lastSeen >= cutoff }
    }

    // MARK: - Debug

    var activeCount: Int { entries.count }

    var activeEntries: [Entry] {
        let cutoff = Date().addingTimeInterval(-freshnessWindow)
        return entries.values.filter { $0.lastSeen >= cutoff }
                              .sorted { $0.lastSeen > $1.lastSeen }
    }
}
