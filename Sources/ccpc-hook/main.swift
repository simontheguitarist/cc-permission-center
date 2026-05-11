import Darwin
import Foundation

// ccpc-hook: bridge between Claude Code hooks and CC Permission Center.app.
//
// stdin:  Claude hook JSON payload
// stdout: Claude hook decision JSON (PreToolUse only emits) — or empty for no-op
// exit code 0 always.
//
// If the app isn't running (socket connect fails), we exit silently so
// Claude Code falls through to its built-in permission prompt.

// MARK: - Helpers

func silentExit() -> Never { exit(0) }

func debugLog(_ message: String) {
    let path = "/tmp/ccpc-hook-debug.log"
    let line = "\(Date()) \(message)\n"
    if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

func socketPath() -> String {
    let support = NSString(string: "~/Library/Application Support").expandingTildeInPath
    return support + "/ch.simk.ccpermissioncenter/ipc.sock"
}

func stdinJSON() -> [String: Any]? {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard !data.isEmpty else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func prettyJSON(_ obj: Any?) -> String {
    guard let obj else { return "" }
    if let s = obj as? String { return s }
    guard JSONSerialization.isValidJSONObject(obj),
          let data = try? JSONSerialization.data(
              withJSONObject: obj,
              options: [.prettyPrinted, .sortedKeys]
          ),
          let s = String(data: data, encoding: .utf8) else { return "" }
    return s
}

// MARK: - Read Claude payload

guard let root = stdinJSON() else { silentExit() }
debugLog("hook fired event=\(root["hook_event_name"] ?? "?") tool=\(root["tool_name"] ?? "?") stop=\(root["stop_reason"] ?? "?") notif=\(root["notification_type"] ?? "?")")

let hookEvent = root["hook_event_name"] as? String ?? "PreToolUse"
let sessionId = root["session_id"] as? String ?? ""
let cwd = root["cwd"] as? String ?? ""
let toolName = root["tool_name"] as? String ?? ""
let permissionMode = root["permission_mode"] as? String ?? "default"
let transcriptPath = root["transcript_path"] as? String ?? ""
let notificationType = root["notification_type"] as? String ?? ""
let toolInputPretty = prettyJSON(root["tool_input"])
let toolInputJSON: String = {
    guard let input = root["tool_input"],
          JSONSerialization.isValidJSONObject(input),
          let data = try? JSONSerialization.data(withJSONObject: input),
          let s = String(data: data, encoding: .utf8) else { return "" }
    return s
}()

// MARK: - Event/tool filter
//
// For PreToolUse, only intercept tools that typically prompt for permission.
// Everything else falls through to Claude's default flow (auto-allow checks, etc).
// Notification + Stop are wired up in settings.json now but handled in a later milestone.

// Tools we know never prompt — Claude auto-allows them regardless of mode.
// AskUserQuestion *isn't* in this list: the hook forwards it so the app can
// surface a "Claude is asking" banner when you're not focused on the
// originating terminal (the app handles its own auto-allow logic).
let alwaysSafe: Set<String> = [
    "Glob", "Grep", "LS", "TodoWrite", "ExitPlanMode", "WebSearch",
]
// Tools that auto-allow in acceptEdits mode on top of the always-safe list.
let acceptEditsSafe: Set<String> = [
    "Edit", "Write", "MultiEdit", "NotebookEdit",
]

switch hookEvent {
case "PreToolUse":
    switch permissionMode {
    case "default":
        if alwaysSafe.contains(toolName) { silentExit() }
    case "acceptEdits":
        if alwaysSafe.contains(toolName) || acceptEditsSafe.contains(toolName) {
            silentExit()
        }
    case "plan", "auto", "dontAsk", "bypassPermissions":
        // Claude handles these modes entirely; we stay out of the way.
        silentExit()
    default:
        silentExit()
    }
case "Notification":
    // Permission prompt notifications duplicate PreToolUse; skip them.
    if notificationType == "permission_prompt" { silentExit() }
case "Stop":
    break
default:
    silentExit()
}

// MARK: - Terminal info
//
// Walk the parent-process chain to find the terminal app that hosts this
// Claude Code session. The hook's direct parent is `claude`, then a shell,
// then the terminal app. We carry the terminal's pid so the app can later
// activate it for "Jump to terminal".

func parentPID(of pid: pid_t) -> pid_t? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    let result = mib.withUnsafeMutableBufferPointer { ptr in
        sysctl(ptr.baseAddress, 4, &info, &size, nil, 0)
    }
    guard result == 0 else { return nil }
    return info.kp_eproc.e_ppid
}

func executablePath(of pid: pid_t) -> String? {
    var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    let n = proc_pidpath(pid, &buf, UInt32(buf.count))
    guard n > 0 else { return nil }
    return String(cString: buf)
}

/// Returns (terminalPID, displayKey) where displayKey is one of: iTerm2,
/// Terminal, VSCode, Conductor, Ghostty, Warp, or nil if no known terminal
/// ancestor is found. Prefers the main app process; falls back to a helper
/// process if the walk runs out before reaching the main binary.
func findTerminalAncestor(startingFrom start: pid_t) -> (pid: pid_t, key: String)? {
    var current = start
    var helperCandidate: (pid: pid_t, key: String)?
    for _ in 0..<24 {
        guard let parent = parentPID(of: current), parent > 1 else { break }
        current = parent
        guard let path = executablePath(of: current) else { continue }

        // Main-app matches: return immediately.
        if path.hasSuffix("/iTerm.app/Contents/MacOS/iTerm2") {
            return (current, "iTerm2")
        }
        if path.hasSuffix("/Terminal.app/Contents/MacOS/Terminal") {
            return (current, "Terminal")
        }
        if path.hasSuffix("/Visual Studio Code.app/Contents/MacOS/Electron")
            || path.hasSuffix("/Visual Studio Code.app/Contents/MacOS/Code") {
            return (current, "VSCode")
        }
        if path.contains("/Conductor.app/Contents/MacOS/") && !path.contains("Helper") {
            return (current, "Conductor")
        }
        if path.hasSuffix("/Ghostty.app/Contents/MacOS/ghostty") {
            return (current, "Ghostty")
        }
        if path.contains("/Warp.app/Contents/MacOS/")
            || path.contains("/WarpPreview.app/Contents/MacOS/") {
            return (current, "Warp")
        }

        // Helper matches: remember as fallback in case the chain terminates
        // before we reach the main app.
        if path.contains("/Visual Studio Code.app/") || path.contains("/Code Helper") {
            helperCandidate = (current, "VSCode")
        }
        if path.contains("/Conductor.app/") {
            helperCandidate = (current, "Conductor")
        }
        if path.contains("/iTerm.app/") {
            helperCandidate = (current, "iTerm2")
        }
    }
    return helperCandidate
}

let env = ProcessInfo.processInfo.environment
let ancestor = findTerminalAncestor(startingFrom: getpid())

let terminalApp: String = {
    if let key = ancestor?.key { return key }
    return env["TERM_PROGRAM"] ?? ""
}()

let terminal: [String: Any] = [
    "app": terminalApp,
    "iterm_session_id": env["ITERM_SESSION_ID"] ?? "",
    "pid": Int(ancestor?.pid ?? getppid()),
]

// MARK: - Build IPC request

var request: [String: Any] = [
    "type": "prompt",
    "session_id": sessionId,
    "cwd": cwd,
    "tool_name": toolName,
    "tool_input_pretty": toolInputPretty,
    "tool_input_json": toolInputJSON,
    "hook_event_name": hookEvent,
    "transcript_path": transcriptPath,
    "permission_mode": permissionMode,
    "terminal": terminal,
]
if hookEvent == "Notification" {
    request["notification_type"] = notificationType
}
if hookEvent == "Stop" {
    request["stop_reason"] = root["stop_reason"] as? String ?? ""
}

guard JSONSerialization.isValidJSONObject(request),
      let requestData = try? JSONSerialization.data(withJSONObject: request) else {
    silentExit()
}

// Debug: if CCPC_DEBUG_DUMP=1, print the IPC request to stderr and exit
// without contacting the socket. Useful for testing terminal detection.
if env["CCPC_DEBUG_DUMP"] == "1" {
    if let pretty = try? JSONSerialization.data(
        withJSONObject: request,
        options: [.prettyPrinted, .sortedKeys]
    ), let s = String(data: pretty, encoding: .utf8) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }
    silentExit()
}

// MARK: - Connect

let path = socketPath()
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { silentExit() }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)

let pathBytes = Array(path.utf8) + [0]
let pathCap = MemoryLayout.size(ofValue: addr.sun_path)
guard pathBytes.count <= pathCap else { close(fd); silentExit() }

withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
    tuplePtr.withMemoryRebound(to: CChar.self, capacity: pathCap) { cstr in
        for (i, b) in pathBytes.enumerated() {
            cstr[i] = CChar(bitPattern: b)
        }
    }
}

let connectResult = withUnsafePointer(to: &addr) { p in
    p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connectResult == 0 else {
    close(fd)
    silentExit()
}

// Receive timeout (60s — matches app side)
var tv = timeval(tv_sec: 60, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

// MARK: - Send request (newline-framed)

var payload = requestData
payload.append(0x0a)
let sent: Int = payload.withUnsafeBytes { ptr in
    var remaining = payload.count
    var offset = 0
    while remaining > 0 {
        let base = ptr.baseAddress!.advanced(by: offset)
        let n = Darwin.send(fd, base, remaining, 0)
        if n <= 0 { return offset }
        offset += n
        remaining -= n
    }
    return offset
}
guard sent == payload.count else { close(fd); silentExit() }

// MARK: - Read response

var responseBuf = Data()
let chunkSize = 4096
var chunk = [UInt8](repeating: 0, count: chunkSize)
while responseBuf.count < 65536 {
    let n = chunk.withUnsafeMutableBufferPointer { ptr -> Int in
        Darwin.recv(fd, ptr.baseAddress, chunkSize, 0)
    }
    if n <= 0 { break }
    responseBuf.append(chunk, count: n)
    if responseBuf.last == 0x0a { break }
}
close(fd)

guard !responseBuf.isEmpty,
      let respObj = try? JSONSerialization.jsonObject(with: responseBuf) as? [String: Any],
      let decision = respObj["decision"] as? String else {
    silentExit()
}

// MARK: - Emit Claude hook output (PreToolUse only)

if hookEvent == "PreToolUse" {
    let permissionDecision: String
    switch decision {
    case "allow": permissionDecision = "allow"
    case "deny":  permissionDecision = "deny"
    case "ask":   permissionDecision = "ask"
    default:      silentExit()
    }

    let output: [String: Any] = [
        "hookSpecificOutput": [
            "hookEventName": "PreToolUse",
            "permissionDecision": permissionDecision,
            "permissionDecisionReason": "via CC Permission Center",
        ],
    ]
    if let data = try? JSONSerialization.data(withJSONObject: output),
       let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

exit(0)
