import Foundation

public struct Ranked: Sendable, Identifiable {
    public let item: Item
    public let score: Int
    /// Matched character offsets in the title; empty when an alternative name matched.
    public let highlights: [Int]

    public var id: String { item.id }

    public init(item: Item, score: Int, highlights: [Int] = []) {
        self.item = item
        self.score = score
        self.highlights = highlights
    }
}

public enum Ranker {
    /// The best `limit` candidates for `query`, best first.
    public static func rank(
        _ candidates: [Candidate], query: String, usage: Usage, now: Date, limit: Int
    ) -> [Ranked] {
        let q = Fuzzy.prepare(query)
        guard !q.isEmpty, limit > 0 else { return [] }
        let words = Fuzzy.prepareWords(query)
        let booster = usage.booster(for: query, at: now)
        // Only the best few are ever shown, so keep those in order instead of sorting every match.
        var top: [(ranked: Ranked, name: [UInt32])] = []
        top.reserveCapacity(limit + 1)
        for candidate in candidates {
            var best: Match?
            var bestIsTitle = false
            for (index, name) in candidate.names.enumerated() {
                let found =
                    candidate.matchesWordStarts ? Fuzzy.wordPrefixMatch(words, in: name) : Fuzzy.match(q, in: name)
                guard let match = found, match.score > (best?.score ?? .min) else { continue }
                best = match
                bestIsTitle = index == 0
            }
            var matchScore = best?.score
            var highlightsTitle = bestIsTitle
            if !candidate.keywords.isEmpty, let keywordScore = Fuzzy.keywordScore(q, candidate.keywords),
                keywordScore > (matchScore ?? .min)
            {
                matchScore = keywordScore
                highlightsTitle = false
            }
            guard let matchScore else { continue }
            let score = matchScore + candidate.weight + booster.boost(for: candidate.item.id)
            let name = candidate.names[0].keys
            if top.count == limit, let last = top.last, !isOrderedBefore(score, name, last) {
                continue
            }
            let entry = (
                Ranked(item: candidate.item, score: score, highlights: highlightsTitle ? best?.positions ?? [] : []),
                name
            )
            let index = top.firstIndex { !isOrderedBefore($0.ranked.score, $0.name, entry) } ?? top.count
            top.insert(entry, at: index)
            if top.count > limit { top.removeLast() }
        }
        return top.map(\.ranked)
    }

    /// Higher score first; on a tie the shorter name, then alphabetical by folded name. A one-letter query
    /// ties hundreds of names, so this compares the keys already folded for matching rather than calling
    /// `localizedStandardCompare`, which costs more than the match itself.
    static func isOrderedBefore(_ score: Int, _ name: [UInt32], _ other: (ranked: Ranked, name: [UInt32])) -> Bool {
        if score != other.ranked.score { return score > other.ranked.score }
        if name.count != other.name.count { return name.count < other.name.count }
        return name.lexicographicallyPrecedes(other.name)
    }
}
