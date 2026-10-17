import AppKit
import CommandKit
import QuickLookUI

/// Quick Look beside the launcher, as Spotlight shows a preview. A non-activating panel that can't take
/// focus: the keyboard stays in the search field, so the selection moves on with the preview following,
/// and nothing changes which app is active.
final class PreviewPanel: NSPanel {
    private let view: QLPreviewView

    init() {
        view = QLPreviewView(frame: .zero, style: .normal)
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .modalPanel
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        view.autoresizingMask = [.width, .height]
        clip.addSubview(view)
        contentView = clip
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static let width: CGFloat = 440
    static let gap: CGFloat = 10

    /// Shows `url`, top-aligned with `panel`, on whichever side of it has room on its screen.
    func show(_ url: URL, beside panel: NSRect, size: PanelSize) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
        let height = max(panel.height, 380)
        let screen = NSScreen.screens.first { $0.frame.intersects(panel) }?.visibleFrame ?? panel
        var x = panel.maxX + Self.gap
        if x + Self.width > screen.maxX { x = panel.minX - Self.gap - Self.width }
        let radius = size.cardRadius
        contentView?.layer?.cornerRadius = radius
        // A layer's colour is fixed when set, so resolve it in this panel's light or dark appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        setFrame(NSRect(x: x, y: panel.maxY - height, width: Self.width, height: height), display: true)
        contentView?.subviews.first?.frame = contentView?.bounds ?? .zero
        orderFront(nil)
        invalidateShadow()
    }
}
