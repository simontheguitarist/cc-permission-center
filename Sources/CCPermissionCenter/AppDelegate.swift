import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let promptController = PromptController()
    private let bannerController = BannerController()
    private let socketServer = SocketServer()
    private let sessionRegistry = SessionRegistry()
    private var stopFollowUpHandled: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        startSocketServer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer.stop()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = makeMenuBarIcon()
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func makeMenuBarIcon() -> NSImage {
        let image = NSImage(systemSymbolName: "bell.fill",
                            accessibilityDescription: "CC Permission Center") ?? NSImage()
        image.isTemplate = true
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Status
        let installed = HookInstaller.isInstalled
        let status = NSMenuItem(
            title: installed ? "✓  Hooks installed" : "⚠︎  Hooks not installed",
            action: nil, keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())

        // Install/uninstall actions
        if installed {
            let reinstall = NSMenuItem(
                title: "Re-install Hooks",
                action: #selector(installHooks), keyEquivalent: ""
            )
            reinstall.target = self
            menu.addItem(reinstall)

            let uninstall = NSMenuItem(
                title: "Uninstall Hooks",
                action: #selector(uninstallHooks), keyEquivalent: ""
            )
            uninstall.target = self
            menu.addItem(uninstall)
        } else {
            let install = NSMenuItem(
                title: "Install Hooks…",
                action: #selector(installHooks), keyEquivalent: ""
            )
            install.target = self
            menu.addItem(install)
        }

        menu.addItem(.separator())

        // Active sessions
        let sessions = sessionRegistry.activeEntries
        let sessionsHeader = NSMenuItem(
            title: sessions.isEmpty
                ? "No active sessions"
                : "Active sessions (\(sessions.count))",
            action: nil, keyEquivalent: ""
        )
        sessionsHeader.isEnabled = false
        menu.addItem(sessionsHeader)
        for s in sessions.prefix(8) {
            let base = (s.cwd as NSString).lastPathComponent
            let project = base.isEmpty ? s.cwd : base
            let term = s.terminal?.displayName ?? "—"
            let item = NSMenuItem(
                title: "    \(project) · \(term)",
                action: nil, keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let loginEnabled = SMAppService.mainApp.status == .enabled
        let loginItem = NSMenuItem(
            title: loginEnabled ? "✓  Open at Login" : "○  Open at Login",
            action: #selector(toggleOpenAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        menu.addItem(loginItem)

        let quit = NSMenuItem(
            title: "Quit CC Permission Center",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
    }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .notRegistered, .notFound:
                try service.register()
            case .requiresApproval:
                // Open System Settings → Login Items so the user can approve.
                let alert = NSAlert()
                alert.messageText = "Approval needed"
                alert.informativeText = "CC Permission Center is registered as a login item but needs your approval in System Settings → General → Login Items. Open it now?"
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    SMAppService.openSystemSettingsLoginItems()
                }
                return
            @unknown default:
                break
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change login item"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Install actions

    @objc private func installHooks() {
        do {
            try HookInstaller.install()
            let alert = NSAlert()
            alert.messageText = "Hooks installed"
            alert.informativeText = "CC Permission Center is now wired into ~/.claude/settings.json. Existing Claude Code sessions need to be restarted to pick up the change."
            alert.alertStyle = .informational
            alert.runModal()
        } catch {
            showError("Install failed", error)
        }
    }

    @objc private func uninstallHooks() {
        let confirm = NSAlert()
        confirm.messageText = "Uninstall hooks?"
        confirm.informativeText = "This removes CC Permission Center entries from ~/.claude/settings.json. Your other hooks (chime sounds, etc.) are kept untouched."
        confirm.addButton(withTitle: "Uninstall")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            try HookInstaller.uninstall()
            let alert = NSAlert()
            alert.messageText = "Hooks uninstalled"
            alert.alertStyle = .informational
            alert.runModal()
        } catch {
            showError("Uninstall failed", error)
        }
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Pull the first question's header out of an AskUserQuestion tool input
    /// so we can show it as a banner subtitle.
    private static func firstAskUserQuestionHeader(toolInputJSON: String) -> String {
        guard let data = toolInputJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let questions = obj["questions"] as? [[String: Any]],
              let first = questions.first
        else { return "" }
        return (first["header"] as? String) ?? ""
    }

private func bannerSubtitle(notificationType: String?,
                                terminalLine: String?,
                                lastMessage: String?) -> String {
        // Prefer Claude's actual message when available (e.g. the question
        // it just asked). Cap to one line worth of text.
        if let msg = lastMessage, !msg.isEmpty, notificationType == "idle_prompt" {
            let oneLine = msg.split(whereSeparator: { $0.isNewline })
                .first.map { String($0) } ?? msg
            return String(oneLine.prefix(180))
        }

        let event: String
        switch notificationType ?? "" {
        case "idle_prompt":     event = "waiting for input"
        case "auth_success":    event = "auth succeeded"
        case "permission_prompt": event = "permission needed"
        case "":                event = "notification"
        default:                event = notificationType ?? "notification"
        }
        if let terminalLine, !terminalLine.isEmpty {
            return "\(event) · \(terminalLine)"
        }
        return event
    }

    // MARK: - Socket

    private func startSocketServer() {
        socketServer.delegate = self
        do {
            try socketServer.start(socketPath: IPCConstants.socketPath)
            NSLog("CCPC listening on \(IPCConstants.socketPath)")
        } catch {
            NSLog("CCPC failed to start socket server: \(error)")
        }
    }
}

extension AppDelegate: SocketServerDelegate {
    nonisolated func socketServer(_ server: SocketServer,
                                  didReceive request: HookRequest,
                                  respond: @escaping (HookDecision) -> Void) {
        Task { @MainActor in
            self.sessionRegistry.touch(
                sessionId: request.sessionId,
                cwd: request.cwd,
                terminal: request.terminal
            )

            let (project, terminalLine) = self.sessionRegistry.projectLabel(
                sessionId: request.sessionId,
                cwd: request.cwd,
                terminal: request.terminal
            )

            let onOriginatingTerminal = TerminalFocus.isUserOnOriginatingTerminal(request.terminal)

            switch request.hookEventName {
            case "PreToolUse":
                // AskUserQuestion always auto-allows so Claude's in-chat
                // picker can render. If you're not on the originating
                // terminal, surface the big top-center question modal
                // (read-only, just a heads-up — answer in Claude's picker).
                if request.toolName == "AskUserQuestion" {
                    respond(.allow)
                    if !onOriginatingTerminal {
                        let header = Self.firstAskUserQuestionHeader(
                            toolInputJSON: request.toolInputJSON ?? ""
                        )
                        let subtitle = header.isEmpty
                            ? "Claude is asking"
                            : "asking: \(header)"
                        self.bannerController.show(
                            title: project,
                            subtitle: subtitle,
                            kind: .idle,
                            duration: 12,
                            onJump: { TerminalJumper.jump(to: request.terminal) }
                        )
                    }
                    return
                }

                // For everything else, if the user is already focused on
                // the originating terminal we bow out and let Claude's
                // native prompt handle things.
                if onOriginatingTerminal {
                    respond(.ask)
                    return
                }

                let permReq = PermissionRequest(
                    id: UUID(),
                    sessionId: request.sessionId,
                    projectLabel: project,
                    terminalDisplay: terminalLine,
                    toolName: request.toolName,
                    toolInput: request.toolInputPretty,
                    toolInputJSON: request.toolInputJSON ?? "",
                    cwd: request.cwd
                )
                let terminalForJump = request.terminal
                self.promptController.show(
                    request: permReq,
                    onDecide: { decision in
                        switch decision {
                        case .approve: respond(.allow)
                        case .deny:    respond(.deny)
                        case .ask:     respond(.ask)
                        }
                    },
                    onJump: {
                        TerminalJumper.jump(to: terminalForJump)
                        respond(.ask)
                    }
                )

            case "Notification":
                let lastMessage = TranscriptReader.lastAssistantText(
                    transcriptPath: request.transcriptPath ?? ""
                )
                let subtitle = self.bannerSubtitle(
                    notificationType: request.notificationType,
                    terminalLine: terminalLine,
                    lastMessage: lastMessage
                )
                self.bannerController.show(
                    title: project,
                    subtitle: subtitle,
                    kind: .idle,
                    duration: 12,
                    onJump: { TerminalJumper.jump(to: request.terminal) }
                )
                respond(.ask)

            case "Stop":
                respond(.ask)
                // Dedupe rapid Stop firings within a turn so we only banner once.
                let key = request.sessionId
                if self.stopFollowUpHandled == key { return }
                self.stopFollowUpHandled = key
                self.bannerController.show(
                    title: project,
                    subtitle: terminalLine.map { "needs your input · \($0)" }
                        ?? "needs your input",
                    kind: .idle,
                    duration: 12,
                    onJump: { TerminalJumper.jump(to: request.terminal) }
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    if self?.stopFollowUpHandled == key {
                        self?.stopFollowUpHandled = ""
                    }
                }

            default:
                respond(.ask)
            }
        }
    }
}
