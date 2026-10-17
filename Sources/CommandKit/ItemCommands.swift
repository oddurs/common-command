import Foundation

/// What can be done with a result besides opening it: the action menu (⌘K, or a right-click), in the
/// order Finder lists the same things.
public enum ItemCommand: Equatable, Sendable {
    case open
    case showInFinder
    case quickLook
    case copyPath
    case copyText(String)
    case quit
    case hide

    public var title: String {
        switch self {
        case .open: "Open"
        case .showInFinder: "Show in Finder"
        case .quickLook: "Quick Look"
        case .copyPath: "Copy Path"
        case .copyText: "Copy"
        case .quit: "Quit"
        case .hide: "Hide"
        }
    }

    /// The key that does the same from the panel, shown beside the menu item.
    public var shortcut: (key: String, command: Bool, shift: Bool)? {
        switch self {
        case .open: ("\r", false, false)
        case .showInFinder: ("\r", true, false)
        case .quickLook: ("y", true, false)
        case .copyPath, .copyText: ("c", true, true)
        case .quit, .hide: nil
        }
    }

    public var symbol: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .showInFinder: "folder"
        case .quickLook: "eye"
        case .copyPath, .copyText: "doc.on.doc"
        case .quit: "xmark.circle"
        case .hide: "eye.slash"
        }
    }

    /// The commands for `item`. `isRunning` adds Hide and Quit for an app that's open. A calculation's
    /// only command is Copy, which is also what Return does.
    public static func commands(for item: Item, isRunning: Bool) -> [ItemCommand] {
        if item.fileURL != nil {
            var commands: [ItemCommand] = [.open, .showInFinder, .quickLook, .copyPath]
            if item.kind == .application, isRunning { commands += [.hide, .quit] }
            return commands
        }
        switch item.action {
        case .open(let url): return [.open, .copyText(url.absoluteString)]
        case .copy(let text): return [.copyText(text)]
        default: return [.open]
        }
    }
}
