import AppKit
import Foundation

enum TerminalJumper {
    static func jump(to terminal: TerminalInfo?) {
        guard let terminal else { return }
        switch terminal.app ?? "" {
        case "iTerm2":
            jumpToITerm(sessionId: terminal.itermSessionId, pid: terminal.pid)
        case "Terminal":
            jumpToTerminalApp(pid: terminal.pid)
        case "VSCode", "Conductor", "Ghostty", "Warp":
            activate(pid: terminal.pid)
        default:
            activate(pid: terminal.pid)
        }
    }

    // MARK: - Helpers

    private static func activate(pid: Int?) {
        guard let pid, pid > 0 else { return }
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            app.activate()
        }
    }

    /// iTerm2 supports per-session AppleScript targeting; fall back to PID
    /// activation if AppleScript fails (e.g. automation permission denied).
    private static func jumpToITerm(sessionId: String?, pid: Int?) {
        if let raw = sessionId, !raw.isEmpty {
            let uuid = raw.split(separator: ":").last.map(String.init) ?? raw
            let escaped = uuid.replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application id "com.googlecode.iterm2"
                activate
                repeat with theWindow in windows
                    repeat with theTab in tabs of theWindow
                        repeat with theSession in sessions of theTab
                            if (id of theSession) is "\(escaped)" then
                                tell theWindow to set current tab to theTab
                                tell theTab to select theSession
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
            var error: NSDictionary?
            if let s = NSAppleScript(source: script) {
                _ = s.executeAndReturnError(&error)
                if error == nil { return }
                NSLog("iTerm AppleScript jump failed: \(error ?? [:])")
            }
        }
        activate(pid: pid)
    }

    private static func jumpToTerminalApp(pid: Int?) {
        activate(pid: pid)
    }
}
