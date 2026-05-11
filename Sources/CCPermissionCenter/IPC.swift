import Foundation

struct HookRequest: Decodable {
    let type: String
    let sessionId: String
    let cwd: String
    let toolName: String
    let toolInputPretty: String
    let toolInputJSON: String?
    let hookEventName: String
    let transcriptPath: String?
    let permissionMode: String?
    let terminal: TerminalInfo?
    let notificationType: String?
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case type
        case sessionId = "session_id"
        case cwd
        case toolName = "tool_name"
        case toolInputPretty = "tool_input_pretty"
        case toolInputJSON = "tool_input_json"
        case hookEventName = "hook_event_name"
        case transcriptPath = "transcript_path"
        case permissionMode = "permission_mode"
        case terminal
        case notificationType = "notification_type"
        case stopReason = "stop_reason"
    }
}

struct TerminalInfo: Decodable {
    let app: String?
    let itermSessionId: String?
    let pid: Int?

    enum CodingKeys: String, CodingKey {
        case app
        case itermSessionId = "iterm_session_id"
        case pid
    }

    /// Human-readable label, e.g. "iTerm2" or "VS Code".
    var displayName: String? {
        guard let app, !app.isEmpty else { return nil }
        switch app {
        // New (M4) ancestor-walk keys
        case "iTerm2":      return "iTerm2"
        case "Terminal":    return "Terminal"
        case "VSCode":      return "VS Code"
        case "Conductor":   return "Conductor"
        case "Ghostty":     return "Ghostty"
        case "Warp":        return "Warp"
        // TERM_PROGRAM fallbacks
        case "iTerm.app":      return "iTerm2"
        case "vscode":         return "VS Code"
        case "Apple_Terminal": return "Terminal"
        case "ghostty":        return "Ghostty"
        case "WarpTerminal":   return "Warp"
        default:               return app
        }
    }
}

enum HookDecision: String {
    case allow
    case deny
    case ask
}

enum IPCConstants {
    static var socketPath: String {
        let support = (NSString(string: "~/Library/Application Support").expandingTildeInPath as String)
        return support + "/ch.simk.ccpermissioncenter/ipc.sock"
    }
}
