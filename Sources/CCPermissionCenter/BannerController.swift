import AppKit
import SwiftUI

@MainActor
final class BannerController {
    private struct Entry {
        let panel: NSPanel
        var timer: Timer?
    }

    /// Newest banner first.
    private var stack: [Entry] = []
    private let bannerWidth: CGFloat = 360
    private let bannerSpacing: CGFloat = 4
    private let edgeInset: CGFloat = 16

    func show(
        title: String,
        subtitle: String?,
        kind: BannerKind,
        duration: TimeInterval = 5,
        onJump: (@MainActor () -> Void)? = nil
    ) {
        NSLog("CCPC Banner.show title=\(title) subtitle=\(subtitle ?? "nil") kind=\(kind)")
        // Build the SwiftUI view. The onDismiss / onJump closures need access
        // to the panel, which we create after sizing — so we wire them with a
        // box-holder.
        var panelHolder: NSPanel?

        let view = BannerView(
            title: title,
            subtitle: subtitle,
            kind: kind,
            onJump: onJump.map { jump in
                { [weak self] in
                    jump()
                    if let p = panelHolder { self?.dismiss(panel: p) }
                }
            },
            onDismiss: { [weak self] in
                if let p = panelHolder { self?.dismiss(panel: p) }
            }
        )

        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panelHolder = panel
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        // Skip collectionBehavior — see PromptController for the reason.
        panel.ignoresMouseEvents = false

        positionPanel(panel, indexFromTop: stack.count)
        panel.orderFrontRegardless()
        NSLog("CCPC Banner #\(stack.count) frame=\(panel.frame) content=\(panel.contentLayoutRect)")

        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) {
            [weak self] _ in
            Task { @MainActor in self?.dismiss(panel: panel) }
        }

        stack.insert(Entry(panel: panel, timer: timer), at: 0)
        relayout()
    }

    private func positionPanel(_ panel: NSPanel, indexFromTop: Int) {
        // Always show on the menu-bar screen so banners are predictable —
        // mouse-based selection puts them on whichever monitor the cursor
        // happens to be on, which may not be where you're looking.
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let frame = panel.frame

        let x = visible.maxX - frame.width - edgeInset
        let yTop = visible.maxY - edgeInset - frame.height
        let y = yTop - CGFloat(indexFromTop) * (frame.height + bannerSpacing)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func relayout() {
        for (index, entry) in stack.enumerated() {
            positionPanel(entry.panel, indexFromTop: index)
        }
    }

    private func dismiss(panel: NSPanel) {
        guard let idx = stack.firstIndex(where: { $0.panel === panel }) else { return }
        let entry = stack.remove(at: idx)
        entry.timer?.invalidate()
        entry.panel.orderOut(nil)
        relayout()
    }

    func dismissAll() {
        for entry in stack {
            entry.timer?.invalidate()
            entry.panel.orderOut(nil)
        }
        stack.removeAll()
    }
}
