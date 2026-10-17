import Foundation
import Testing

@testable import CommandKit

/// Regression gates, not benchmarks of record. Budgets sit roughly 10x above what an M-series Mac
/// measures, so they catch an accidental quadratic loop without flaking on a busy CI runner.
@Suite(.serialized)
struct PerformanceTests {
    /// The mean of the fastest of five batches. Other work on the machine can only slow a batch down, never
    /// speed it up, so the fastest batch is the closest to the code's own cost. An average over everything
    /// let one busy moment fail the gate on a loaded Mac.
    func averageMicroseconds(_ iterations: Int, _ body: () -> Void) -> Double {
        body()
        var fastest = UInt64.max
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<iterations { body() }
            fastest = min(fastest, DispatchTime.now().uptimeNanoseconds - start)
        }
        return Double(fastest) / Double(iterations) / 1000
    }

    /// Two thousand plausible names: far more apps and panes than any Mac has.
    static let catalog: [Candidate] = {
        let words = [
            "Safari", "Mail", "Studio", "Code", "Visual", "System", "Settings", "Photo", "Pro", "Music", "Notes",
            "Terminal", "Utility", "Disk", "Activity", "Monitor", "Preview", "Calendar", "Messages", "Final",
        ]
        // Deterministic, so every run measures the same work.
        return (0..<2000).map { i in
            let name = (0...(i % 4)).map { k in words[(i * 7 + k * 13) % words.count] }.joined(separator: " ")
            return app("\(name) \(i)")
        }
    }()

    /// About 0.6 ms in a release build on an M4 Pro, and 10 ms in the debug build the suite runs.
    @Test(arguments: ["s", "vsc", "system settings", "zzz"])
    func rankingTheWholeCatalogTakesWellUnderAFrame(query: String) {
        let catalog = Self.catalog
        let now = Date()
        let us = averageMicroseconds(4) {
            _ = Ranker.rank(catalog, query: query, usage: Usage(), now: now, limit: 8)
        }
        print("rank 2,000 for \"\(query)\": \(String(format: "%.0f", us)) µs")
        #expect(us < 40_000)
    }

    @Test func scanningTheApplicationsFoldersIsFast() {
        let us = averageMicroseconds(3) { _ = AppCatalog.scan() }
        print("scan apps: \(String(format: "%.0f", us)) µs")
        #expect(us < 500_000)
    }
}
