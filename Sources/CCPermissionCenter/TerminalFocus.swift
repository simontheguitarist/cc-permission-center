import AppKit
import Foundation

/// Decides whether the user is currently focused on the exact terminal
/// session that fired the hook. If so, we suppress the popup so Claude's
/// native in-terminal prompt isn't redundant.
enum TerminalFocus {
    @MainActor
    static func isUserOnOriginatingTerminal(_ info: TerminalInfo?) -> Bool {
        guard let info,
              let frontmost = NSWorkspace.shared.frontmostApplication
        else { return false }

        switch info.app ?? "" {
        case "iTerm2":
            guard frontmost.bundleIdentifier == "com.googlecode.iterm2" else { return false }
            return frontmostITermSessionMatches(info.itermSessionId)
        case "Terminal":
            // No per-tab ID — bringing-to-front gives matching app; close enough.
            return frontmost.bundleIdentifier == "com.apple.Terminal"
        case "VSCode":
            return frontmost.bundleIdentifier?.hasPrefix("com.microsoft.VSCode") == true
                || frontmost.bundleIdentifier == "com.microsoft.VSCode"
        case "Conductor":
            // Conductor's bundle id is unknown ahead of time; match by PID.
            return info.pid.map { Int32($0) } == frontmost.processIdentifier
        case "Ghostty":
            return frontmost.bundleIdentifier == "com.mitchellh.ghostty"
        case "Warp":
            return frontmost.bundleIdentifier == "dev.warp.Warp-Stable"
                || frontmost.bundleIdentifier == "dev.warp.Warp"
        default:
            return false
        }
    }

    private static func frontmostITermSessionMatches(_ rawSessionId: String?) -> Bool {
        guard let raw = rawSessionId, !raw.isEmpty else {
            NSLog("CCPC focus: no ITERM_SESSION_ID on the request")
            return false
        }
        let expected = raw.split(separator: ":").last.map(String.init) ?? raw
        let script = """
        tell application id "com.googlecode.iterm2"
            try
                return id of current session of current tab of current window
            on error errMsg
                return "ERR:" & errMsg
            end try
        end tell
        """
        var error: NSDictionary?
        guard let s = NSAppleScript(source: script) else { return false }
        let result = s.executeAndReturnError(&error)
        if let err = error {
            NSLog("CCPC focus: AppleScript error: \(err)")
            return false
        }
        let actual = result.stringValue ?? ""
        NSLog("CCPC focus: iTerm current session=\(actual) expected=\(expected) match=\(actual == expected)")
        return actual == expected
    }
}
