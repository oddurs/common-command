/// A name prepared for matching once, when the catalog is built, so a keystroke only does the comparison.
public struct SearchText: Sendable, Hashable {
    public let string: String
    let keys: [UInt32]
    let bonus: [Int16]

    /// Names longer than this match on their first part only; nothing worth launching is named that long.
    static let maximumLength = 96

    public init(_ string: String) {
        self.string = string
        var keys: [UInt32] = []
        var bonus: [Int16] = []
        var previous: Character?
        for character in string.prefix(Self.maximumLength) {
            keys.append(fold(character))
            bonus.append(Self.bonus(character, after: previous))
            previous = character
        }
        self.keys = keys
        self.bonus = bonus
    }

    /// Word starts are what people type: "vsc" for Visual Studio Code, "ss" for System Settings.
    static func bonus(_ c: Character, after previous: Character?) -> Int16 {
        guard let previous else { return 10 }
        if !previous.isLetter && !previous.isNumber { return c.isLetter || c.isNumber ? 9 : 0 }
        if c.isUppercase && previous.isLowercase { return 8 }
        if c.isLetter && previous.isNumber { return 6 }
        return 0
    }
}

/// Case and accent folding to one scalar per character, so positions line up with the original string.
func fold(_ c: Character) -> UInt32 {
    if c.isASCII, let ascii = c.asciiValue {
        return UInt32(ascii >= 65 && ascii <= 90 ? ascii + 32 : ascii)
    }
    let folded = String(c).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    return folded.unicodeScalars.first?.value ?? 0
}

public struct Match: Equatable, Sendable {
    public var score: Int
    /// Character offsets into the matched name, for highlighting.
    public var positions: [Int]
}

/// Scores a query against a name: every query character must appear in order. Matches on word starts and
/// runs of consecutive characters score highest, gaps cost a little, and a shorter name wins a tie.
public enum Fuzzy {
    static let matchScore = 16
    static let consecutiveBonus = 6
    static let gapStart = -3
    static let gapExtend = -1
    static let exactBonus = 40
    static let unmatched = Int.min / 4

    /// The query with whitespace removed and folded, ready to match many names.
    public static func prepare(_ query: String) -> [UInt32] {
        query.filter { !$0.isWhitespace }.map(fold)
    }

    public static func match(_ query: String, in text: SearchText) -> Match? {
        match(prepare(query), in: text)
    }

    public static func match(_ q: [UInt32], in text: SearchText) -> Match? {
        let m = q.count
        let n = text.keys.count
        guard m > 0, m <= n, isSubsequence(q, of: text.keys) else { return nil }
        // Runs once per name per keystroke, so the table lives on the stack rather than the heap.
        return withUnsafeTemporaryAllocation(of: Int.self, capacity: m * n) { table in
            q.withUnsafeBufferPointer { q in
                text.keys.withUnsafeBufferPointer { t in
                    text.bonus.withUnsafeBufferPointer { bonus in
                        align(q, t, bonus, table)
                    }
                }
            }
        }
    }

    private static func align(
        _ q: UnsafeBufferPointer<UInt32>, _ t: UnsafeBufferPointer<UInt32>, _ bonus: UnsafeBufferPointer<Int16>,
        _ h: UnsafeMutableBufferPointer<Int>
    ) -> Match? {
        let m = q.count
        let n = t.count
        // h[i * n + j]: the best score with query character i matched at name character j.
        h.initialize(repeating: unmatched)
        for i in 0..<m {
            var gapBest = unmatched
            for j in i..<n {
                if i > 0 && j >= 2 {
                    gapBest = max(gapBest + gapExtend, h[(i - 1) * n + j - 2] + gapStart)
                }
                guard t[j] == q[i] else { continue }
                let base = matchScore + Int(bonus[j])
                if i == 0 {
                    // A small cost for starting late, so a prefix beats the same letters mid-name.
                    h[j] = base - min(j, 5)
                } else {
                    let consecutive = h[(i - 1) * n + j - 1]
                    let best = max(consecutive == unmatched ? unmatched : consecutive + consecutiveBonus, gapBest)
                    if best > unmatched { h[i * n + j] = base + best }
                }
            }
        }

        var end = -1
        var best = unmatched
        for j in (m - 1)..<n where h[(m - 1) * n + j] > best {
            best = h[(m - 1) * n + j]
            end = j
        }
        guard end >= 0 else { return nil }

        var positions = [Int](repeating: 0, count: m)
        positions[m - 1] = end
        var j = end
        for i in stride(from: m - 1, to: 0, by: -1) {
            let needed = h[i * n + j] - matchScore - Int(bonus[j])
            let consecutive = h[(i - 1) * n + j - 1]
            if consecutive != unmatched && consecutive + consecutiveBonus == needed {
                j -= 1
            } else {
                var k = j - 2
                while k >= 0 && h[(i - 1) * n + k] + gapStart + gapExtend * (j - k - 2) != needed { k -= 1 }
                j = max(k, 0)
            }
            positions[i - 1] = j
        }

        var score = best - (n - m) / 4
        if m == n { score += exactBonus }
        return Match(score: score, positions: positions)
    }

    /// A stricter match for long, numerous names such as System Settings topics: each typed word must start
    /// a word of the name, in order. "low power" finds "Low Power Mode"; "saf" doesn't find "Screen area
    /// for display", which as initials would. Scored like a run of word-start matches.
    public static func wordPrefixMatch(_ words: [[UInt32]], in text: SearchText) -> Match? {
        guard !words.isEmpty else { return nil }
        let t = text.keys
        var cursor = 0
        var positions: [Int] = []
        for word in words {
            var found: Int?
            var start = cursor
            while start + word.count <= t.count {
                if text.bonus[start] > 0, t[start..<(start + word.count)].elementsEqual(word) {
                    found = start
                    break
                }
                start += 1
            }
            guard let found else { return nil }
            positions += Array(found..<(found + word.count))
            cursor = found + word.count
        }
        let m = positions.count
        let starts = words.count
        var score = matchScore * m + consecutiveBonus * (m - starts) + 9 * starts - (t.count - m) / 4
        if positions.first == 0 { score += 1 }
        if m == t.count { score += exactBonus }
        return Match(score: score, positions: positions)
    }

    /// The query's words, folded, for `wordPrefixMatch`.
    public static func prepareWords(_ query: String) -> [[UInt32]] {
        query.split(whereSeparator: \.isWhitespace).map { $0.map(fold) }
    }

    static let minimumKeywordLength = 4

    /// A keyword the query starts: below a name that starts the same way, above a scattered name match.
    static func keywordScore(_ q: [UInt32], _ keywords: [[UInt32]]) -> Int? {
        // Three letters are nearly always the start of an app's name, and hundreds of keywords would match.
        guard q.count >= minimumKeywordLength else { return nil }
        var best: Int?
        for keyword in keywords where keyword.count >= q.count && keyword.starts(with: q) {
            let score = 12 * q.count + 8 + (keyword.count == q.count ? 10 : 0)
            best = max(best ?? score, score)
        }
        return best
    }

    static func isSubsequence(_ q: [UInt32], of t: [UInt32]) -> Bool {
        var i = 0
        for c in t where c == q[i] {
            i += 1
            if i == q.count { return true }
        }
        return false
    }
}
