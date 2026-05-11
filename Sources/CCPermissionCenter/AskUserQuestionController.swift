import AppKit
import SwiftUI

@MainActor
final class AskUserQuestionController {
    private var panel: NSPanel?
    private let hotkeys = HotkeyManager()
    private var onDismissAction: (() -> Void)?
    private var onJumpAction: (() -> Void)?

    func show(projectLabel: String,
              terminalDisplay: String?,
              question: AUQQuestion,
              terminal: TerminalInfo?,
              onSelect: @escaping (AUQOption) -> Void,
              onJump: @escaping () -> Void,
              onDismiss: @escaping () -> Void) {
        // Dismiss any prior question.
        dismiss()

        onJumpAction = { [weak self] in
            onJump()
            self?.dismiss()
        }
        onDismissAction = { [weak self] in
            onDismiss()
            self?.dismiss()
        }

        let view = AskUserQuestionView(
            projectLabel: projectLabel,
            terminalDisplay: terminalDisplay,
            question: question,
            onSelect: { [weak self] option in
                onSelect(option)
                self?.dismiss()
            },
            onJump: { [weak self] in self?.onJumpAction?() },
            onDismiss: { [weak self] in self?.onDismissAction?() }
        )

        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setContentSize(size)
        panel.contentView = hosting
        positionTopCenter(panel)
        panel.orderFrontRegardless()
        self.panel = panel

        registerHotkeys()
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        hotkeys.unregisterAll()
        onDismissAction = nil
        onJumpAction = nil
    }

    private func registerHotkeys() {
        hotkeys.register([
            HotkeyManager.Binding(
                id: 21, keyCode: HotkeyKey.j, modifiers: HotkeyModifiers.ctrlOpt
            ) { [weak self] in self?.onJumpAction?() },
            HotkeyManager.Binding(
                id: 22, keyCode: HotkeyKey.r, modifiers: HotkeyModifiers.ctrlOpt
            ) { [weak self] in self?.onDismissAction?() },
        ])
    }

    private func positionTopCenter(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSPointInRect(mouse, $0.frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let frame = panel.frame
        let origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.maxY - frame.height - 24
        )
        panel.setFrameOrigin(origin)
    }
}

/// Sends a string + Enter to the originating terminal session. Only iTerm2
/// supports per-session writes; others are best-effort no-ops with a fallback.
enum TerminalInput {
    static func send(_ text: String, to terminal: TerminalInfo?) -> Bool {
        guard let terminal else { return false }
        switch terminal.app ?? "" {
        case "iTerm2":
            return sendToITerm(text, sessionId: terminal.itermSessionId)
        default:
            // No reliable per-session write for other terminals yet.
            return false
        }
    }

    private static func sendToITerm(_ text: String, sessionId: String?) -> Bool {
        guard let raw = sessionId, !raw.isEmpty else { return false }
        let uuid = raw.split(separator: ":").last.map(String.init) ?? raw
        let escapedUUID = uuid.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application id "com.googlecode.iterm2"
            repeat with theWindow in windows
                repeat with theTab in tabs of theWindow
                    repeat with theSession in sessions of theTab
                        if (id of theSession) is "\(escapedUUID)" then
                            tell theSession to write text "\(escapedText)"
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
            return "notfound"
        end tell
        """
        var error: NSDictionary?
        guard let s = NSAppleScript(source: script) else { return false }
        let result = s.executeAndReturnError(&error)
        if let err = error {
            NSLog("CCPC TerminalInput: AppleScript error: \(err)")
            return false
        }
        return (result.stringValue ?? "") == "ok"
    }
}
