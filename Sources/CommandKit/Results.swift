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

/// Puts one query's results in order: a web address or calculation first, since typing one is
/// unambiguous, then apps and settings, then files, then the web search that's always there.
public enum Results {
    public static func compose(
        query: String, candidates: [Candidate], files: [Candidate], usage: Usage, now: Date,
        options: SearchOptions
    ) -> [Ranked] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        var results: [Ranked] = []

        if let url = Web.address(text) {
            let item = Item(
                id: "link:" + url.absoluteString, title: url.absoluteString, subtitle: "Open Link", kind: .link,
                action: .open(url))
            results.append(Ranked(item: item, score: .max))
        }
        if options.calculator, let value = Calculator.evaluate(text, locale: options.locale) {
            let shown = Calculator.format(value, locale: options.locale)
            let copied = Calculator.format(value, locale: options.locale, grouping: false)
            let item = Item(
                id: "calc", title: "= " + shown, subtitle: "Copy", kind: .calculation, action: .copy(copied))
            results.append(Ranked(item: item, score: .max))
        }
        results += Ranker.rank(candidates, query: text, usage: usage, now: now, limit: options.limit)
        results += Ranker.rank(files, query: text, usage: usage, now: now, limit: options.fileLimit)
        if options.webSearch, let url = options.engine.url(searching: text) {
            let item = Item(
                id: "web", title: text, subtitle: "Search \(options.engine.name)", kind: .webSearch,
                action: .open(url))
            results.append(Ranked(item: item, score: .min))
        }
        return results
    }
}
