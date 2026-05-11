import AppKit
import SwiftUI

@MainActor
final class QuestionController {
    private var panel: NSPanel?
    private let hotkeys = HotkeyManager()
    private var dismissTimer: Timer?
    private var currentOnJump: (() -> Void)?

    func show(projectLabel: String,
              terminalDisplay: String?,
              question: String,
              onJump: @escaping () -> Void) {
        // If a previous question is up, drop it.
        dismiss()
        currentOnJump = onJump

        let view = QuestionView(
            projectLabel: projectLabel,
            terminalDisplay: terminalDisplay,
            question: question,
            onJump: { [weak self] in
                self?.currentOnJump?()
                self?.dismiss()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
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

        // Auto-dismiss after 30s.
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) {
            [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
        panel = nil
        hotkeys.unregisterAll()
        currentOnJump = nil
    }

    private func registerHotkeys() {
        hotkeys.register([
            HotkeyManager.Binding(
                id: 11, keyCode: HotkeyKey.j, modifiers: HotkeyModifiers.ctrlOpt
            ) { [weak self] in
                self?.currentOnJump?()
                self?.dismiss()
            },
            HotkeyManager.Binding(
                id: 12, keyCode: HotkeyKey.r, modifiers: HotkeyModifiers.ctrlOpt
            ) { [weak self] in
                self?.dismiss()
            },
        ])
    }

    /// Mirror the prompt's top-center positioning so questions feel like
    /// part of the same flow.
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
