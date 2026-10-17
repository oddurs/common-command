import AppKit
import CommandKit

/// One entry in the action menu: the command's name, symbol, and key, running a closure when chosen.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(command: ItemCommand, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: command.title, action: #selector(runHandler), keyEquivalent: command.shortcut?.key ?? "")
        target = self
        image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil)
        if let shortcut = command.shortcut {
            var modifiers: NSEvent.ModifierFlags = []
            if shortcut.command { modifiers.insert(.command) }
            if shortcut.shift { modifiers.insert(.shift) }
            keyEquivalentModifierMask = modifiers
        }
    }

    required init(coder: NSCoder) { fatalError("not used from a nib") }

    @objc private func runHandler() { handler() }
}
