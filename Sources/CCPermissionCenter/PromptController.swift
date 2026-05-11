import AppKit
import SwiftUI

@MainActor
final class PromptController {
    private var panel: NSPanel?
    private let hotkeys = HotkeyManager()

    private struct Pending {
        let request: PermissionRequest
        let onDecide: (PermissionRequest.Decision) -> Void
        let onJump: () -> Void
    }

    /// Pending prompts waiting their turn; oldest first.
    private var queue: [Pending] = []
    private var active: Pending?

    func show(request: PermissionRequest,
              onDecide: @escaping (PermissionRequest.Decision) -> Void,
              onJump: @escaping () -> Void) {
        let pending = Pending(request: request, onDecide: onDecide, onJump: onJump)
        if active == nil {
            present(pending)
        } else {
            queue.append(pending)
        }
    }

    var queueCount: Int { queue.count }

    private func present(_ pending: Pending) {
        active = pending
        let view = PromptView(
            request: pending.request,
            pendingCount: queue.count,
            onDecide: { [weak self] decision in
                self?.complete(.decision(decision))
            },
            onJump: { [weak self] in
                self?.complete(.jump)
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
    }

    private enum Resolution {
        case decision(PermissionRequest.Decision)
        case jump
    }

    private func complete(_ resolution: Resolution) {
        guard let current = active else { return }
        active = nil
        dismissPanel()
        hotkeys.unregisterAll()

        switch resolution {
        case .decision(let d):
            current.onDecide(d)
        case .jump:
            current.onJump()
        }

        // Drain the queue.
        if !queue.isEmpty {
            let next = queue.removeFirst()
            // Tiny pause so the user notices the new prompt is a different one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.present(next)
            }
        }
    }

    private func dismissPanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func registerHotkeys() {
        hotkeys.register([
            HotkeyManager.Binding(
                id: 1, keyCode: HotkeyKey.a, modifiers: HotkeyModifiers.ctrlOpt
            ) { [weak self] in self?.complete(.decision(.approve)) },
            HotkeyManager.Binding(
                id: 2, keyCode: HotkeyKey.r, modifiers: HotkeyModifiers.ctrlOpt
            ) { [weak self] in self?.complete(.decision(.deny)) },
            HotkeyManager.Binding(
                id: 3, keyCode: HotkeyKey.j, modifiers: HotkeyModifiers.ctrlOpt
            ) { [weak self] in self?.complete(.jump) },
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
