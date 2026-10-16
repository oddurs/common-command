import CommandKit
import CoreServices
import Foundation
import os

/// Everything that can be searched, and what has been chosen before.
@MainActor
final class Library {
    private(set) var apps: [Candidate] = []
    private(set) var panes: [Candidate] = []
    var commands: [Candidate] = []
    private(set) var usage: Usage
    var onChange: (() -> Void)?

    private var scannedAt: Date?
    private var scanning = false
    /// Long enough that opening the panel twice in a row doesn't rescan, short enough that a newly
    /// installed app shows up the next time you look for it.
    private static let staleAfter: TimeInterval = 30

    nonisolated private static let log = Logger(subsystem: "com.oddurs.commoncommand", category: "usage")

    private static var usageURL: URL {
        URL.applicationSupportDirectory.appending(path: "Common Command/usage.json")
    }

    init() {
        usage =
            (try? Data(contentsOf: Self.usageURL)).flatMap { try? JSONDecoder().decode(Usage.self, from: $0) }
            ?? Usage()
    }

    func candidates(includingPanes: Bool) -> [Candidate] {
        includingPanes ? apps + panes + commands : apps + commands
    }

    /// Rescans in the background; the current lists keep answering until the new ones arrive.
    func refreshIfStale() {
        guard !scanning, scannedAt.map({ Date().timeIntervalSince($0) > Self.staleAfter }) ?? true else { return }
        scanning = true
        let needsPanes = panes.isEmpty
        Task {
            let (apps, panes) = await Task.detached(priority: .userInitiated) {
                (AppCatalog.scan(), needsPanes ? SettingsPanes.scan() : [])
            }.value
            self.apps = apps
            // System Settings changes only with macOS, so its panes are read once per launch.
            if needsPanes { self.panes = panes }
            scannedAt = Date()
            scanning = false
            onChange?()
        }
    }

    func record(_ item: Item, query: String) {
        usage.record(item.id, query: query, at: Date())
        let usage = usage
        let url = Self.usageURL
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(usage).write(to: url, options: .atomic)
            } catch {
                // Losing one launch from the history isn't worth interrupting anyone over.
                Library.log.error("couldn't save usage: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Files by name, from the Spotlight index. MDQuery rather than NSMetadataQuery because it can cap the
/// result count, so a one-letter query returns in milliseconds instead of gathering every match.
enum FileSearch {
    static let maximumResults = 60

    static func run(_ query: String) -> [Candidate] {
        guard let string = FileQuery.spotlightQuery(for: query),
            let mdQuery = MDQueryCreate(kCFAllocatorDefault, string as CFString, nil, nil)
        else { return [] }
        MDQuerySetSearchScope(mdQuery, ["kMDQueryScopeHome"] as CFArray, 0)
        MDQuerySetMaxCount(mdQuery, maximumResults)
        guard MDQueryExecute(mdQuery, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let now = Date()
        return (0..<MDQueryGetResultCount(mdQuery)).compactMap { index in
            guard let raw = MDQueryGetResultAtIndex(mdQuery, index) else { return nil }
            let mdItem = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(mdItem, "kMDItemPath" as CFString) as? String,
                !isClutter(path)
            else { return nil }
            let lastUsed = MDItemCopyAttribute(mdItem, "kMDItemLastUsedDate" as CFString) as? Date
            let type = MDItemCopyAttribute(mdItem, "kMDItemContentType" as CFString) as? String
            return candidate(path: path, isFolder: type == "public.folder", lastUsed: lastUsed, home: home, now: now)
        }
    }

    /// Caches, app internals, dot-folders, and build output match plenty of names and are never what
    /// anyone is looking for.
    static let clutter = ["/Library/", "/.", ".app/", "/node_modules/", "/target/", "/DerivedData/", "/__pycache__/"]

    static func isClutter(_ path: String) -> Bool {
        clutter.contains { path.contains($0) }
    }

    static func candidate(path: String, isFolder: Bool, lastUsed: Date?, home: String, now: Date) -> Candidate {
        let url = URL(filePath: path, directoryHint: isFolder ? .isDirectory : .notDirectory)
        let parent = url.deletingLastPathComponent().path
        let shown = parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
        let item = Item(
            id: "file:" + path, title: url.lastPathComponent, subtitle: shown, kind: isFolder ? .folder : .file,
            action: .open(url))
        // Something opened this week is more likely the one you mean than something from years ago, and
        // either beats a file nobody has ever opened, which is usually generated.
        let weight: Int
        if let lastUsed {
            let age = now.timeIntervalSince(lastUsed)
            weight = age < 7 * 86400 ? 8 : age < 30 * 86400 ? 4 : 0
        } else {
            weight = -12
        }
        return Candidate(item, weight: weight)
    }
}
