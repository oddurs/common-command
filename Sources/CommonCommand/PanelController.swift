import AppKit
import CommandKit
import SwiftUI

/// A borderless panel that takes typing without activating the app, so the app you were in stays
/// frontmost, its menu bar stays put, and closing the panel returns you to it with nothing to restore.
final class CommandPanel: NSPanel {
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    var onModifiersChange: ((NSEvent.ModifierFlags) -> Void)?

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .modalPanel
        hidesOnDeactivate = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        // On the current Space, including over full-screen apps, and never in ⌘` or Mission Control.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onKeyEquivalent?(event) == true || super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged { onModifiersChange?(event.modifierFlags) }
        super.sendEvent(event)
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let model: SearchModel
    private let preferences: Preferences
    private let library: Library
    private let panel = CommandPanel()
    private weak var field: NSTextField?
    private var builtFor: (size: PanelSize, translucent: Bool)?
    var perform: ((Item, _ reveal: Bool) -> Void)?

    /// How far down the screen the panel's top edge sits: high, like Spotlight, but clear of the menu bar.
    private static let topFraction: CGFloat = 0.2

    init(preferences: Preferences, library: Library) {
        self.preferences = preferences
        self.library = library
        model = SearchModel(library: library, preferences: preferences)
        super.init()
        panel.delegate = self
        panel.onKeyEquivalent = { [weak self] in self?.keyEquivalent($0) ?? false }
        panel.onModifiersChange = { [weak self] flags in
            self?.model.showsShortcuts = flags.intersection(.deviceIndependentFlagsMask) == .command
        }
        model.onResultsChange = { [weak self] in self?.resize() }
        library.onChange = { [weak self] in
            guard let self, panel.isVisible else { return }
            model.update(keepingSelection: true)
        }
    }

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        library.refreshIfStale()
        buildContentIfNeeded()
        panel.appearance = preferences.theme.appearance
        model.showsShortcuts = false
        model.update()
        position()
        panel.makeKeyAndOrderFront(nil)
        refreshShadow()
        // The last query comes back selected, so typing replaces it and ↩ repeats it.
        if let field {
            panel.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    func preferencesChanged() {
        guard isVisible else { return }
        buildContentIfNeeded()
        panel.appearance = preferences.theme.appearance
        model.update(keepingSelection: true)
    }

    // MARK: Choosing

    private func choose(_ index: Int, reveal: Bool = false) {
        guard model.results.indices.contains(index) else { return }
        let item = model.results[index].item
        library.record(item, query: model.query)
        hide()
        perform?(item, reveal)
    }

    private func keyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, let key = event.charactersIgnoringModifiers else { return false }
        if key == "\r" {
            choose(model.selection, reveal: true)
            return true
        }
        if let digit = Int(key), (1...9).contains(digit) {
            choose(digit - 1)
            return true
        }
        return false
    }

    // MARK: Layout

    private func buildContentIfNeeded() {
        let size = preferences.size
        let translucent = preferences.translucent
        if let builtFor, builtFor == (size, translucent) { return }
        builtFor = (size, translucent)

        let commands = SearchField.Commands(
            move: { [weak self] in self?.model.move($0) },
            submit: { [weak self] in
                guard let self else { return }
                choose(model.selection)
            },
            cancel: { [weak self] in self?.hide() },
            made: { [weak self] in self?.field = $0 })
        let hosting = NSHostingView(
            rootView: PanelView(model: model, preferences: preferences, commands: commands) { [weak self] in
                self?.choose($0)
            })
        hosting.sizingOptions = []
        let background = Self.background(around: hosting, size: size, translucent: translucent)
        // Clipped to the panel's shape, so the window's shadow is rounded too and not a rectangle.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = size.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        panel.contentView = container
        background.frame = container.bounds
    }

    /// Liquid Glass on macOS 26, the popover material before it, or nothing when the view draws its own
    /// solid background.
    private static func background(around content: NSView, size: PanelSize, translucent: Bool) -> NSView {
        guard translucent else { return content }
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = size.cornerRadius
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(radius: size.cornerRadius)
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
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

    /// Centred on the screen with the pointer, which is the screen you're looking at.
    private func position() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let top = visible.maxY - visible.height * Self.topFraction
        let size = preferences.size
        let height = size.height(rows: model.results.count, visible: preferences.visibleRows)
        panel.setFrame(
            NSRect(x: (visible.midX - size.width / 2).rounded(), y: top - height, width: size.width, height: height),
            display: false)
    }

    /// Grows and shrinks downward, so the field stays under your eyes while results come and go.
    private func resize() {
        guard panel.isVisible || panel.frame.width > 0 else { return }
        let size = preferences.size
        let height = size.height(rows: model.results.count, visible: preferences.visibleRows)
        guard panel.frame.height != height || panel.frame.width != size.width else { return }
        let top = panel.frame.maxY
        panel.setFrame(
            NSRect(x: panel.frame.midX - size.width / 2, y: top - height, width: size.width, height: height),
            display: false)
        refreshShadow()
    }

    /// The shadow follows the window's shape as last drawn, so it's recomputed once the new frame has
    /// rendered: a turn of the run loop later, rather than forcing a draw while a key is being handled.
    private func refreshShadow() {
        DispatchQueue.main.async { [panel] in panel.invalidateShadow() }
    }
}
