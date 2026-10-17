import AppKit
import CommandKit
import SwiftUI

/// A borderless panel that takes typing without activating the app, so the app you were in stays
/// frontmost, its menu bar stays put, and closing the panel returns you to it with nothing to restore.
final class CommandPanel: NSPanel {
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    var onPointerMove: (() -> Void)?

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
        acceptsMouseMovedEvents = true
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
        // Before the event reaches the rows' hover tracking, so they know the pointer really moved.
        if event.type == .mouseMoved { onPointerMove?() }
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
    private var content: PanelContent?
    private var builtFor: (size: PanelSize, translucent: Bool)?
    var perform: ((Item, _ reveal: Bool) -> Void)?

    /// How far down the screen the panel's top edge sits: high, like Spotlight, but clear of the menu bar.
    private static let topFraction: CGFloat = 0.2
    /// Short enough that typing straight away never waits on it.
    private static let fadeDuration: TimeInterval = 0.12

    init(preferences: Preferences, library: Library) {
        self.preferences = preferences
        self.library = library
        model = SearchModel(library: library, preferences: preferences)
        super.init()
        panel.delegate = self
        panel.onKeyEquivalent = { [weak self] in self?.keyEquivalent($0) ?? false }
        panel.onPointerMove = { [weak self] in self?.model.pointerMoved = true }
        model.onResultsChange = { [weak self] in self?.resize() }
        library.onChange = { [weak self] in
            guard let self, panel.isVisible else { return }
            model.update(keepingSelection: true)
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        library.refreshIfStale()
        buildContentIfNeeded()
        panel.appearance = preferences.theme.appearance
        library.refreshRunningApps()
        model.scope = .all
        model.pointerMoved = false
        model.update()
        position()
        // A quick fade, as macOS shows its own panels; none at all with Reduce Motion.
        let fades = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = fades ? 0 : 1
        panel.makeKeyAndOrderFront(nil)
        if fades {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                panel.animator().alphaValue = 1
            }
        }
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
        // ⌘1, ⌘2, ⌘3 choose Apps, Files, or Actions, and pressing it again goes back to everything.
        if let scope = Scope.scoped.first(where: { $0.key == key.first }) {
            toggle(scope)
            return true
        }
        return false
    }

    /// What `show()` reads fresh, without showing anything.
    func prepareForSnapshot() {
        library.refreshRunningApps()
    }

    func toggle(_ scope: Scope) {
        model.scope = model.scope == scope ? .all : scope
    }

    /// Escape leaves a scope first, like deleting a search token, and closes the panel after that.
    private func cancel() {
        if model.scope != .all {
            model.scope = .all
        } else {
            hide()
        }
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
            cancel: { [weak self] in self?.cancel() },
            leaveScope: { [weak self] in
                guard let self, model.scope != .all else { return false }
                model.scope = .all
                return true
            },
            toggleScope: { [weak self] in self?.toggle($0) },
            made: { [weak self] in self?.field = $0 })
        let content = PanelContent(
            size: size, translucent: translucent,
            field: FieldView(model: model, preferences: preferences, commands: commands),
            card: CardView(model: model, preferences: preferences) { [weak self] in self?.choose($0) })
        self.content = content
        panel.contentView = content
    }

    /// The panel as it would look now, drawn offscreen with solid surfaces, since glass only renders on
    /// screen. For design review: nothing appears and nothing takes focus.
    func renderOffscreen(appearance: NSAppearance?) -> NSBitmapImageRep? {
        let size = preferences.size
        let noop = SearchField.Commands(
            move: { _ in }, submit: {}, cancel: {}, leaveScope: { false }, toggleScope: { _ in }, made: { _ in })
        let content = PanelContent(
            size: size, translucent: false,
            field: FieldView(model: model, preferences: preferences, commands: noop),
            card: CardView(model: model, preferences: preferences) { _ in })
        let margin: CGFloat = 24
        let frame = NSRect(x: 0, y: 0, width: size.width + 2 * margin, height: height + 2 * margin)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        let backdrop = NSView(frame: frame)
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.35).cgColor
        content.frame = NSRect(x: margin, y: margin, width: size.width, height: height)
        backdrop.addSubview(content)
        window.contentView = backdrop
        window.appearance = appearance
        backdrop.layoutSubtreeIfNeeded()
        backdrop.displayIfNeeded()
        guard let rep = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) else { return nil }
        backdrop.cacheDisplay(in: backdrop.bounds, to: rep)
        return rep
    }

    /// A second model for the preview in Settings, searching "s" so it shows a few sections.
    private(set) lazy var previewModel: SearchModel = {
        let model = SearchModel(library: library, preferences: preferences)
        model.query = "s"
        return model
    }()

    /// The panel as it looks with the current settings, for Settings to show. It doesn't take input.
    func makePreview() -> PanelContent {
        let noop = SearchField.Commands(
            move: { _ in }, submit: {}, cancel: {}, leaveScope: { false }, toggleScope: { _ in },
            made: { field in
                field.isEditable = false
                field.isSelectable = false
                field.refusesFirstResponder = true
            })
        return PanelContent(
            size: preferences.size, translucent: preferences.translucent,
            field: FieldView(model: previewModel, preferences: preferences, commands: noop),
            card: CardView(model: previewModel, preferences: preferences) { _ in })
    }

    func previewHeight() -> CGFloat {
        let size = preferences.size
        return size.height(
            rows: previewModel.results.count, headers: previewModel.sections.count, visible: preferences.visibleRows)
    }

    /// The panel's height for what the model shows now.
    private var height: CGFloat {
        let size = preferences.size
        if model.showsNoResults { return size.height(rows: 1, headers: 0, visible: preferences.visibleRows) }
        return size.height(
            rows: model.results.count, headers: model.sections.count, visible: preferences.visibleRows)
    }

    /// Centred on the screen with the pointer, which is the screen you're looking at.
    private func position() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let top = visible.maxY - visible.height * Self.topFraction
        let size = preferences.size
        let height = height
        panel.setFrame(
            NSRect(x: (visible.midX - size.width / 2).rounded(), y: top - height, width: size.width, height: height),
            display: false)
    }

    /// Grows and shrinks downward, so the field stays under your eyes while results come and go.
    private func resize() {
        guard panel.isVisible || panel.frame.width > 0 else { return }
        let size = preferences.size
        let height = height
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
