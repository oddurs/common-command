import AppKit
import CommandKit
import SwiftUI

/// What the panel holds: the field's capsule and, under it, the results card, each its own piece of glass,
/// as the search field and its results are on macOS 26.
@MainActor
final class PanelContent: NSView {
    private let size: PanelSize
    private let field: NSView
    private let card: NSView

    init(size: PanelSize, translucent: Bool, field: FieldView, card: CardView) {
        self.size = size
        self.field = Self.surface(NSHostingView(rootView: field), radius: size.fieldRadius, translucent: translucent)
        self.card = Self.surface(NSHostingView(rootView: card), radius: size.cardRadius, translucent: translucent)
        super.init(frame: .zero)
        addSubview(self.field)
        addSubview(self.card)
    }

    required init?(coder: NSCoder) { fatalError("not used from a nib") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        field.frame = NSRect(x: 0, y: 0, width: bounds.width, height: size.fieldHeight)
        let cardTop = size.fieldHeight + size.gap
        card.frame = NSRect(x: 0, y: cardTop, width: bounds.width, height: max(0, bounds.height - cardTop))
        card.isHidden = card.frame.height <= 0
    }

    /// Liquid Glass on macOS 26, the popover material before it, or nothing when the SwiftUI view draws a
    /// solid fill. Clipped to the shape, so the window's shadow follows the rounded outline rather than
    /// the rectangle the glass is drawn in.
    private static func surface(_ content: NSHostingView<some View>, radius: CGFloat, translucent: Bool) -> NSView {
        content.sizingOptions = []
        let background: NSView
        if !translucent {
            background = content
        } else if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius
            glass.contentView = content
            background = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            // The window server draws this blur, so only a mask image rounds it; the layer clip doesn't.
            effect.maskImage = roundedMask(radius: radius)
            content.autoresizingMask = [.width, .height]
            effect.addSubview(content)
            background = effect
        }
        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.cornerRadius = radius
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]
        clip.addSubview(background)
        return clip
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
