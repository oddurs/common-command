import Foundation

/// What has been opened, how often, and how recently, and which result was chosen for which query. It
/// moves things you use up the list, makes the query you typed last time pick the same thing again, and
/// lets a shorter or longer start of that query lean the same way.
public struct Usage: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        /// Uses, each decayed by its age, as of `last`.
        var weight: Double
        var last: Date
    }

    var entries: [String: Entry] = [:]
    /// Folded query → the id chosen for it most recently.
    var choices: [String: String] = [:]

    /// A use counts half as much after a week.
    static let halfLife: TimeInterval = 7 * 24 * 3600
    static let maximumEntries = 500
    static let maximumChoices = 1000
    static let choiceBoost = 120
    static let maximumFrecencyBoost = 40

    public init() {}

    public mutating func record(_ id: String, query: String, at now: Date) {
        let entry = entries[id]
        let weight = entry.map { decayed($0, at: now) } ?? 0
        entries[id] = Entry(weight: weight + 1, last: now)
        let key = Self.key(query)
        if !key.isEmpty { choices[key] = id }
        prune(at: now)
    }

    public func boost(for id: String, query: String, at now: Date) -> Int {
        booster(for: query, at: now).boost(for: id)
    }

    /// Boosts for one query, worked out once so ranking many items costs a lookup each.
    public struct Booster: Sendable {
        let choices: [String: Int]
        let usage: Usage
        let now: Date

        public func boost(for id: String) -> Int {
            var boost = choices[id] ?? 0
            if let entry = usage.entries[id] {
                boost += min(Usage.maximumFrecencyBoost, Int(12 * log2(1 + usage.decayed(entry, at: now))))
            }
            return boost
        }
    }

    public func booster(for query: String, at now: Date) -> Booster {
        Booster(choices: choiceBoosts(Self.key(query)), usage: self, now: now)
    }

    /// The exact query earns the full boost. A query that starts a past one ("sa" after choosing Safari for
    /// "safari"), or that a past one starts ("safar" after "saf"), earns a share of half of it, in proportion
    /// to how much of the longer one they have in common.
    func choiceBoosts(_ key: String) -> [String: Int] {
        guard !key.isEmpty else { return [:] }
        var boosts: [String: Int] = [:]
        for (stored, id) in choices {
            let boost: Int
            if stored == key {
                boost = Self.choiceBoost
            } else if stored.hasPrefix(key) || key.hasPrefix(stored) {
                let shared = min(stored.count, key.count)
                boost = Self.choiceBoost / 2 * shared / max(stored.count, key.count)
            } else {
                continue
            }
            boosts[id] = max(boosts[id] ?? 0, boost)
        }
        return boosts
    }

    func decayed(_ entry: Entry, at now: Date) -> Double {
        entry.weight * pow(0.5, max(0, now.timeIntervalSince(entry.last)) / Self.halfLife)
    }

    static func key(_ query: String) -> String {
        String(String.UnicodeScalarView(Fuzzy.prepare(query).compactMap(Unicode.Scalar.init)))
    }

    private mutating func prune(at now: Date) {
        if entries.count > Self.maximumEntries {
            let keep = entries.sorted { decayed($0.value, at: now) > decayed($1.value, at: now) }
                .prefix(Self.maximumEntries)
            entries = Dictionary(uniqueKeysWithValues: Array(keep))
        }
        if choices.count > Self.maximumChoices {
            // Choices carry no date, so drop those whose item has faded the most.
            let ranked = choices.sorted {
                (entries[$0.value].map { decayed($0, at: now) } ?? 0)
                    > (entries[$1.value].map { decayed($0, at: now) } ?? 0)
            }
            choices = Dictionary(uniqueKeysWithValues: Array(ranked.prefix(Self.maximumChoices)))
        }
    }
}
