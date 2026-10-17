import Foundation

public struct SearchOptions: Sendable, Equatable {
    public var calculator = true
    public var webSearch = true
    public var engine = SearchEngine.google
    /// Apps, settings, and commands shown at most.
    public var limit = 8
    public var fileLimit = 5
    public var locale = Locale.current

    public init() {}
}

/// A run of results under one header, as Spotlight groups them.
public struct ResultSection: Identifiable, Sendable {
    public let title: String
    public let rows: [Ranked]

    public var id: String { title }

    public init(title: String, rows: [Ranked]) {
        self.title = title
        self.rows = rows
    }
}

/// Puts one query's results in order and into sections. A web address or a calculation comes first, since
/// typing one is unambiguous. Then the best match on its own as the Top Hit, then the rest grouped by
/// kind, each group placed by its best match, and last the web search that's always there.
public enum Results {
    public static func compose(
        query: String, candidates: [Candidate], files: [Candidate], usage: Usage, now: Date,
        options: SearchOptions
    ) -> [ResultSection] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        var sections: [ResultSection] = []

        if let url = Web.address(text) {
            let item = Item(
                id: "link:" + url.absoluteString, title: url.absoluteString, subtitle: "Open", kind: .link,
                action: .open(url))
            sections.append(ResultSection(title: "Website", rows: [Ranked(item: item, score: .max)]))
        }
        if options.calculator, let conversion = Converter.convert(text, locale: options.locale) {
            let digits = Converter.significantDigits
            let shown = Calculator.format(conversion.value, locale: options.locale, digits: digits)
            let copied = Calculator.format(conversion.value, locale: options.locale, grouping: false, digits: digits)
            let item = Item(
                id: "convert", title: "\(shown) \(conversion.unit)", subtitle: "Copy", kind: .calculation,
                action: .copy(copied))
            sections.append(ResultSection(title: "Conversion", rows: [Ranked(item: item, score: .max)]))
        } else if options.calculator, let value = Calculator.evaluate(text, locale: options.locale) {
            let shown = Calculator.format(value, locale: options.locale)
            let copied = Calculator.format(value, locale: options.locale, grouping: false)
            let item = Item(id: "calc", title: shown, subtitle: "Copy", kind: .calculation, action: .copy(copied))
            sections.append(ResultSection(title: "Calculator", rows: [Ranked(item: item, score: .max)]))
        }

        let ranked = merge(
            Ranker.rank(candidates, query: text, usage: usage, now: now, limit: options.limit),
            Ranker.rank(files, query: text, usage: usage, now: now, limit: options.fileLimit))
        sections += group(ranked)

        if options.webSearch, let url = options.engine.url(searching: text) {
            let item = Item(
                id: "web", title: text, subtitle: options.engine.name, kind: .webSearch, action: .open(url))
            sections.append(ResultSection(title: "Search the Web", rows: [Ranked(item: item, score: .min)]))
        }
        return sections
    }

    /// Two best-first lists as one, best first; on a tie the first list's entry leads.
    static func merge(_ a: [Ranked], _ b: [Ranked]) -> [Ranked] {
        var merged: [Ranked] = []
        merged.reserveCapacity(a.count + b.count)
        var i = 0
        var j = 0
        while i < a.count || j < b.count {
            if j == b.count || (i < a.count && a[i].score >= b[j].score) {
                merged.append(a[i])
                i += 1
            } else {
                merged.append(b[j])
                j += 1
            }
        }
        return merged
    }

    /// The best result as the Top Hit, then the others under their kind's header, groups in order of
    /// their best member.
    static func group(_ ranked: [Ranked]) -> [ResultSection] {
        guard let top = ranked.first else { return [] }
        var order: [String] = []
        var rows: [String: [Ranked]] = [:]
        for result in ranked.dropFirst() {
            let title = header(for: result.item.kind)
            if rows[title] == nil { order.append(title) }
            rows[title, default: []].append(result)
        }
        return [ResultSection(title: "Top Hit", rows: [top])] + order.map { ResultSection(title: $0, rows: rows[$0]!) }
    }

    static func header(for kind: Kind) -> String {
        switch kind {
        case .application: "Applications"
        case .settings: "System Settings"
        case .command: "Common Command"
        case .file, .folder: "Files"
        case .calculation: "Calculator"
        case .link: "Website"
        case .webSearch: "Search the Web"
        }
    }
}

extension [ResultSection] {
    /// Every row in display order: what the selection steps through.
    public var rows: [Ranked] { flatMap(\.rows) }
}
