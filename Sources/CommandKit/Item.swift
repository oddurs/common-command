import Foundation

public enum Kind: String, Sendable, Hashable {
    case application, settings, command, action, file, folder, calculation, link, webSearch
}

/// What choosing a result does.
public enum Action: Sendable, Hashable {
    /// Opens an app, file, folder, or URL with its default handler.
    case open(URL)
    case copy(String)
    /// Handled by the app shell: one of its own commands, such as opening Settings.
    case command(String)
    /// Runs one of the user's shortcuts from the Shortcuts app, by name.
    case shortcut(String)
    /// Quits or hides a running app, by bundle identifier.
    case quit(String)
    case hide(String)
}

/// One row in the results.
public struct Item: Identifiable, Sendable, Hashable {
    /// Stable across launches, so usage history can refer to it.
    public let id: String
    public let title: String
    public let subtitle: String
    public let kind: Kind
    public let action: Action
    /// A file whose icon stands for the item when it isn't a file itself, such as a System Settings pane's
    /// extension.
    public let iconFile: URL?

    public init(id: String, title: String, subtitle: String, kind: Kind, action: Action, iconFile: URL? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.action = action
        self.iconFile = iconFile
    }

    /// The file behind the item, for Reveal in Finder.
    public var fileURL: URL? {
        if case .open(let url) = action, url.isFileURL { return url }
        return nil
    }
}

/// An item with the names it can be found by. The title comes first; the others are alternatives, such
/// as an app's file name when its display name is localised. Keywords match only from their start, the
/// way a word you'd think of matches: "dark" finds the Appearance pane through "Dark Mode".
public struct Candidate: Sendable {
    public let item: Item
    public let names: [SearchText]
    let keywords: [[UInt32]]
    /// Added to every match, so an app outranks a settings pane with an equally good name. Small, so a
    /// clearly closer name still wins: "Bluetooth" the pane over "Bluetooth File Exchange" the app.
    public let weight: Int

    /// Matches only where each typed word starts a word of a name, never as scattered letters or initials.
    let matchesWordStarts: Bool

    public init(
        _ item: Item, alternatives: [String] = [], keywords: [String] = [], weight: Int = 0,
        matchesWordStarts: Bool = false
    ) {
        self.item = item
        self.matchesWordStarts = matchesWordStarts
        var seen: Set<String> = [item.title]
        names = [SearchText(item.title)] + alternatives.filter { seen.insert($0).inserted }.map(SearchText.init)
        // Each keyword whole, spaces dropped, and each of its words, so "darkm" and "mode" both find "Dark Mode".
        var prepared: Set<[UInt32]> = []
        for keyword in keywords {
            prepared.insert(Fuzzy.prepare(keyword))
            for word in keyword.split(whereSeparator: { $0.isWhitespace || $0 == "-" }) {
                prepared.insert(Fuzzy.prepare(String(word)))
            }
        }
        self.keywords = prepared.filter { $0.count >= 2 }.sorted { $0.lexicographicallyPrecedes($1) }
        self.weight = weight
    }
}
