import AppKit
import CommandKit
import SwiftUI

/// The panel at the top of Settings, drawn by the same views as the real one, so theme, size,
/// translucency, and the number of results show as you change them.
struct PanelPreview: View {
    let panel: PanelController
    let size: PanelSize
    let translucent: Bool
    let theme: Theme
    let visibleRows: Int
    /// The width Settings has room for; the preview scales down to it.
    let width: CGFloat

    var body: some View {
        let height = panel.previewHeight()
        let scale = min(1, width / size.width)
        PanelPreviewView(panel: panel, size: size, translucent: translucent, theme: theme, height: height)
            .frame(width: size.width * scale, height: height * scale)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Preview of the panel")
    }
}

/// Holds the panel's content at full size inside a frame scaled to fit, by giving the view smaller
/// bounds than frame: AppKit scales everything inside, glass included.
private struct PanelPreviewView: NSViewRepresentable {
    let panel: PanelController
    let size: PanelSize
    let translucent: Bool
    let theme: Theme
    let height: CGFloat

    final class Container: NSView {
        var built: (PanelSize, Bool)?
        var content: PanelContent?
        var fullSize = NSSize.zero

        override func layout() {
            super.layout()
            guard fullSize.width > 0 else { return }
            bounds = NSRect(origin: .zero, size: fullSize)
            content?.frame = bounds
        }
    }

    func makeNSView(context: Context) -> Container { Container() }

    func updateNSView(_ container: Container, context: Context) {
        if container.built.map({ $0 != (size, translucent) }) ?? true {
            container.content?.removeFromSuperview()
            let content = panel.makePreview()
            container.addSubview(content)
            container.content = content
            container.built = (size, translucent)
        }
        container.appearance = theme.appearance
        container.fullSize = NSSize(width: size.width, height: height)
        container.needsLayout = true
    }
}
