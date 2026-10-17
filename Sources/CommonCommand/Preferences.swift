import AppKit
import CommandKit

enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Every setting, saved to UserDefaults as it changes.
@MainActor @Observable
final class Preferences {
    private let defaults: UserDefaults

    var hotKey: KeyCombo { didSet { save(hotKey, "hotKey") } }
    var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    var size: PanelSize { didSet { defaults.set(size.rawValue, forKey: "size") } }
    var translucent: Bool { didSet { defaults.set(translucent, forKey: "translucent") } }
    var visibleRows: Int { didSet { defaults.set(visibleRows, forKey: "visibleRows") } }
    var searchesSettings: Bool { didSet { defaults.set(searchesSettings, forKey: "searchesSettings") } }
    var searchesFiles: Bool { didSet { defaults.set(searchesFiles, forKey: "searchesFiles") } }
    var calculates: Bool { didSet { defaults.set(calculates, forKey: "calculates") } }
    var searchesWeb: Bool { didSet { defaults.set(searchesWeb, forKey: "searchesWeb") } }
    var searchesActions: Bool { didSet { defaults.set(searchesActions, forKey: "searchesActions") } }
    var engine: SearchEngine { didSet { defaults.set(engine.rawValue, forKey: "engine") } }
    var showsMenuBarItem: Bool { didSet { defaults.set(showsMenuBarItem, forKey: "showsMenuBarItem") } }

    static let visibleRowsRange = 4...12

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "translucent": true, "visibleRows": 8, "searchesSettings": true, "searchesFiles": true, "calculates": true,
            "searchesWeb": true, "searchesActions": true, "showsMenuBarItem": true,
        ])
        hotKey =
            defaults.data(forKey: "hotKey").flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? .standard
        theme = defaults.string(forKey: "theme").flatMap(Theme.init) ?? .system
        size = defaults.string(forKey: "size").flatMap(PanelSize.init) ?? .medium
        translucent = defaults.bool(forKey: "translucent")
        visibleRows = Self.visibleRowsRange.clamp(defaults.integer(forKey: "visibleRows"))
        searchesSettings = defaults.bool(forKey: "searchesSettings")
        searchesFiles = defaults.bool(forKey: "searchesFiles")
        calculates = defaults.bool(forKey: "calculates")
        searchesWeb = defaults.bool(forKey: "searchesWeb")
        searchesActions = defaults.bool(forKey: "searchesActions")
        engine = defaults.string(forKey: "engine").flatMap(SearchEngine.init) ?? .google
        showsMenuBarItem = defaults.bool(forKey: "showsMenuBarItem")
    }

    private func save(_ value: some Encodable, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    var searchOptions: SearchOptions {
        var options = SearchOptions()
        options.calculator = calculates
        options.webSearch = searchesWeb
        options.engine = engine
        return options
    }
}

extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
