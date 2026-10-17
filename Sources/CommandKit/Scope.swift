import Foundation

/// What the search covers, as macOS 26 Spotlight splits it: everything, or only apps, files, or actions.
public enum Scope: String, CaseIterable, Sendable, Identifiable {
    case all, apps, files, actions

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .all: "Everything"
        case .apps: "Apps"
        case .files: "Files"
        case .actions: "Actions"
        }
    }

    /// The SF Symbol on the scope's button in the field.
    public var symbol: String {
        switch self {
        case .all: "magnifyingglass"
        case .apps: "square.grid.2x2"
        case .files: "folder"
        case .actions: "bolt"
        }
    }

    /// ⌘1, ⌘2, ⌘3, as in Spotlight.
    public var key: Character? {
        switch self {
        case .all: nil
        case .apps: "1"
        case .files: "2"
        case .actions: "3"
        }
    }

    public static let scoped: [Scope] = [.apps, .files, .actions]

    func includes(_ kind: Kind) -> Bool {
        switch self {
        case .all: true
        case .apps: kind == .application || kind == .settings || kind == .command
        case .files: kind == .file || kind == .folder
        case .actions: kind == .action
        }
    }
}

/// Things to do rather than open: the user's shortcuts from the Shortcuts app, and quitting or hiding
/// running apps. They rank below apps with an equally good name, so "saf" still means Safari.
public enum Actions {
    static let weight = -6

    /// The names `shortcuts list` prints, one per line.
    public static func shortcutNames(fromList output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public static func shortcuts(_ names: [String], icon: URL?) -> [Candidate] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0).inserted }.map { name in
            Candidate(
                Item(
                    id: "shortcut:" + name, title: name, subtitle: "Shortcut", kind: .action,
                    action: .shortcut(name), iconFile: icon),
                weight: weight)
        }
    }

    public struct RunningApp: Sendable {
        public var name: String
        public var bundleIdentifier: String
        public var url: URL

        public init(name: String, bundleIdentifier: String, url: URL) {
            self.name = name
            self.bundleIdentifier = bundleIdentifier
            self.url = url
        }
    }

    /// "Quit Safari" and "Hide Safari" for each running app with a Dock icon, by app name. They match by
    /// word starts only, so "quit sa" means Quit Safari and never the "sa" inside Quit Messages.
    public static func appActions(_ apps: [RunningApp]) -> [Candidate] {
        apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.flatMap { app in
            [
                Candidate(
                    Item(
                        id: "quit:" + app.bundleIdentifier, title: "Quit \(app.name)", subtitle: "Running",
                        kind: .action, action: .quit(app.bundleIdentifier), iconFile: app.url),
                    weight: weight, matchesWordStarts: true),
                Candidate(
                    Item(
                        id: "hide:" + app.bundleIdentifier, title: "Hide \(app.name)", subtitle: "Running",
                        kind: .action, action: .hide(app.bundleIdentifier), iconFile: app.url),
                    weight: weight, matchesWordStarts: true),
            ]
        }
    }
}
