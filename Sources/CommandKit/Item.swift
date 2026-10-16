import Foundation

public enum Kind: String, Sendable, Hashable {
    case application, settings, command, file, folder, calculation, link, webSearch
}

/// What choosing a result does.
public enum Action: Sendable, Hashable {
    /// Opens an app, file, folder, or URL with its default handler.
    case open(URL)
    case copy(String)
    /// Handled by the app shell: one of its own commands, such as opening Settings.
    case command(String)
}

/// One row in the results.
public struct Item: Identifiable, Sendable, Hashable {
    /// Stable across launches, so usage history can refer to it.
    public let id: String
    public let title: String
    public let subtitle: String
    public let kind: Kind
    public let action: Action

    public init(id: String, title: String, subtitle: String, kind: Kind, action: Action) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.action = action
    }

    /// The file behind the item, for its icon and for Reveal in Finder.
    public var fileURL: URL? {
        if case .open(let url) = action, url.isFileURL { return url }
        return nil
    }
}

/// An item with the names it can be found by. The title comes first; the others are alternatives, such
/// as an app's file name when its display name is localised.
public struct Candidate: Sendable {
    public let item: Item
    public let names: [SearchText]
    /// Added to every match, so an app outranks a settings pane with an equally good name. Small, so a
    /// clearly closer name still wins: "Bluetooth" the pane over "Bluetooth File Exchange" the app.
    public let weight: Int

    public init(_ item: Item, alternatives: [String] = [], weight: Int = 0) {
        self.item = item
        var seen: Set<String> = [item.title]
        names = [SearchText(item.title)] + alternatives.filter { seen.insert($0).inserted }.map(SearchText.init)
        self.weight = weight
    }
}
