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
        let booster = usage.booster(for: query, at: now)
        // Only the best few are ever shown, so keep those in order instead of sorting every match.
        var top: [(ranked: Ranked, length: Int)] = []
        top.reserveCapacity(limit + 1)
        for candidate in candidates {
            var best: Match?
            var bestIsTitle = false
            for (index, name) in candidate.names.enumerated() {
                guard let match = Fuzzy.match(q, in: name), match.score > (best?.score ?? .min) else { continue }
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
            let length = candidate.names[0].keys.count
            if top.count == limit, let last = top.last, !isOrderedBefore(score, length, candidate.item, last) {
                continue
            }
            let entry = (
                Ranked(item: candidate.item, score: score, highlights: highlightsTitle ? best?.positions ?? [] : []),
                length
            )
            let index =
                top.firstIndex { !isOrderedBefore($0.ranked.score, $0.length, $0.ranked.item, entry) } ?? top.count
            top.insert(entry, at: index)
            if top.count > limit { top.removeLast() }
        }
        return top.map(\.ranked)
    }

    /// Higher score first; on a tie the shorter name, then alphabetical.
    static func isOrderedBefore(_ score: Int, _ length: Int, _ item: Item, _ other: (ranked: Ranked, length: Int))
        -> Bool
    {
        if score != other.ranked.score { return score > other.ranked.score }
        if length != other.length { return length < other.length }
        return item.title.localizedStandardCompare(other.ranked.item.title) == .orderedAscending
    }
}
