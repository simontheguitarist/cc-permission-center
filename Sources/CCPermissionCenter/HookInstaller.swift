import Foundation

enum HookInstaller {
    static let hooksDir = NSString(string: "~/.claude/hooks").expandingTildeInPath
    static let hookSymlinkPath = (hooksDir as NSString).appendingPathComponent("ccpc-hook")
    static let settingsPath = NSString(string: "~/.claude/settings.json").expandingTildeInPath
    static let events: [String] = ["PreToolUse", "Notification", "Stop"]

    enum InstallError: Error, LocalizedError {
        case hookBinaryNotFound
        case settingsWriteFailed(Error)

        var errorDescription: String? {
            switch self {
            case .hookBinaryNotFound:
                return "Could not locate the bundled ccpc-hook binary."
            case .settingsWriteFailed(let e):
                return "Failed to update ~/.claude/settings.json: \(e.localizedDescription)"
            }
        }
    }

    static func bundledHookPath() -> String? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let candidate = (resourcePath as NSString).appendingPathComponent("ccpc-hook")
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    static var isInstalled: Bool {
        guard let settings = readSettings(),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        for event in events {
            if anyEntryContainsOurHook(in: hooks[event]) { return true }
        }
        return false
    }

    static func install() throws {
        guard let hookBin = bundledHookPath() else { throw InstallError.hookBinaryNotFound }

        // Ensure hooks dir and refresh the symlink so the path is stable
        // even if the user moves the .app later.
        try FileManager.default.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: hookSymlinkPath) || isSymlink(hookSymlinkPath) {
            try? fm.removeItem(atPath: hookSymlinkPath)
        }
        try fm.createSymbolicLink(atPath: hookSymlinkPath, withDestinationPath: hookBin)

        // Merge into settings.json.
        var settings = readSettings() ?? [:]
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]

        for event in events {
            var entries = (hooks[event] as? [[String: Any]]) ?? []
            entries = strippingOurEntries(from: entries)
            entries.append([
                "hooks": [
                    [
                        "type": "command",
                        "command": hookSymlinkPath,
                    ],
                ],
            ])
            hooks[event] = entries
        }

        settings["hooks"] = hooks
        do {
            try writeSettings(settings)
        } catch {
            throw InstallError.settingsWriteFailed(error)
        }
    }

    static func uninstall() throws {
        var settings = readSettings() ?? [:]
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]

        for event in events {
            guard var entries = hooks[event] as? [[String: Any]] else { continue }
            entries = strippingOurEntries(from: entries)
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        do {
            try writeSettings(settings)
        } catch {
            throw InstallError.settingsWriteFailed(error)
        }

        // Best-effort symlink cleanup.
        try? FileManager.default.removeItem(atPath: hookSymlinkPath)
    }

    // MARK: - Internals

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let raw = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        // JSONSerialization escapes "/" as "\/" — strip that since both forms
        // are valid JSON and the unescaped form matches what users hand-write.
        guard var s = String(data: raw, encoding: .utf8) else {
            throw NSError(domain: "HookInstaller", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "could not utf-8 decode settings"])
        }
        s = s.replacingOccurrences(of: "\\/", with: "/")
        if !s.hasSuffix("\n") { s += "\n" }

        let url = URL(fileURLWithPath: settingsPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try s.data(using: .utf8)!.write(to: url, options: .atomic)
    }

    /// Drop any matcher entry whose `hooks` list references our binary.
    /// If a matcher had OTHER hooks too, keep it with only those.
    private static func strippingOurEntries(from entries: [[String: Any]]) -> [[String: Any]] {
        return entries.compactMap { entry -> [String: Any]? in
            var entry = entry
            guard let inner = entry["hooks"] as? [[String: Any]] else { return entry }
            let kept = inner.filter { !isOurHook($0) }
            if kept.isEmpty { return nil }
            entry["hooks"] = kept
            return entry
        }
    }

    private static func isOurHook(_ entry: [String: Any]) -> Bool {
        guard let cmd = entry["command"] as? String else { return false }
        return cmd.contains("ccpc-hook")
    }

    private static func anyEntryContainsOurHook(in value: Any?) -> Bool {
        guard let entries = value as? [[String: Any]] else { return false }
        for entry in entries {
            guard let inner = entry["hooks"] as? [[String: Any]] else { continue }
            if inner.contains(where: isOurHook) { return true }
        }
        return false
    }

    private static func isSymlink(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFLNK
    }
}
