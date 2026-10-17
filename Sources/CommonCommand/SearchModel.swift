import AppKit
import CommandKit

/// The query, its results, and which one is selected.
@MainActor @Observable
final class SearchModel {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            pointerMoved = false
            update()
        }
    }
    private(set) var sections: [ResultSection] = []
    /// Every row in display order, which is the order the selection moves through.
    private(set) var results: [Ranked] = []
    var selection = 0 {
        didSet {
            announceSelection()
            if selection != oldValue { onSelectionChange?() }
        }
    }
    /// Everything, or only apps, files, or actions. With nothing typed, a scope lists what it holds.
    var scope = Scope.all {
        didSet {
            guard scope != oldValue else { return }
            pointerMoved = false
            files = []
            update()
        }
    }
    /// Whether the pointer has really moved since the last key. Rows change under a still pointer while
    /// you type, and that mustn't take the selection, or Return would open whatever happened to land there.
    @ObservationIgnored var pointerMoved = false

    @ObservationIgnored var onResultsChange: (() -> Void)?
    @ObservationIgnored var onSelectionChange: (() -> Void)?
    @ObservationIgnored private let library: Library
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var files: [Candidate] = []
    @ObservationIgnored private var fileTask: Task<Void, Never>?

    /// Spotlight answers in a few milliseconds, but a query per keystroke while typing fast is wasted work.
    private static let fileDelay = Duration.milliseconds(35)

    init(library: Library, preferences: Preferences) {
        self.library = library
        self.preferences = preferences
    }

    var selected: Item? { results.indices.contains(selection) ? results[selection].item : nil }

    /// Typed something, or chose a scope, and nothing is there.
    var showsNoResults: Bool {
        sections.isEmpty && (scope != .all || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Whether files belong in what's shown now: in Everything if Settings says so, and always in Files.
    private var includesFiles: Bool {
        scope == .files || (scope == .all && preferences.searchesFiles)
    }

    func move(_ delta: Int) {
        pointerMoved = false
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    /// The pointer is over row `index`; it takes the selection only if the pointer got there by moving.
    func hover(_ index: Int) {
        guard pointerMoved, results.indices.contains(index), selection != index else { return }
        selection = index
    }

    /// Recomputes from what's already known, then asks Spotlight for files. A new query selects the
    /// top result. Results that arrive later, such as files or a refreshed app list, keep a selection
    /// you moved, but otherwise the top result stays selected even if it changed.
    func update(keepingSelection: Bool = false) {
        compose(keepingSelection: keepingSelection)
        fileTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing typed in Files lists recent files; otherwise nothing typed needs no files.
        guard includesFiles, !text.isEmpty || scope == .files else {
            files = []
            return
        }
        fileTask = Task {
            try? await Task.sleep(for: Self.fileDelay)
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                text.isEmpty ? FileSearch.recent() : FileSearch.run(text)
            }.value
            guard !Task.isCancelled else { return }
            files = found
            compose(keepingSelection: true)
        }
    }

    private func compose(keepingSelection: Bool) {
        let selectedID = keepingSelection && selection != 0 ? selected?.id : nil
        // Files from the previous keystroke stay until the new ones arrive; ranking drops those that no
        // longer match, so the list doesn't flicker.
        var options = preferences.searchOptions
        options.scope = scope
        // A scope chosen on purpose shows its kind even if Settings leaves it out of Everything.
        let candidates = library.candidates(
            includingPanes: preferences.searchesSettings || scope == .apps,
            includingActions: preferences.searchesActions || scope == .actions)
        sections = Results.compose(
            query: query, candidates: candidates, files: includesFiles ? files : [], usage: library.usage, now: Date(),
            options: options)
        results = sections.rows
        if let selectedID, let index = results.firstIndex(where: { $0.id == selectedID }) {
            selection = index
        } else {
            selection = 0
        }
        onResultsChange?()
        announceSelection()
    }

    @ObservationIgnored private var announcedID: String?

    /// VoiceOver reads the selected result whenever it changes, by key or because typing changed the top
    /// result, so the list can be used without looking at it.
    private func announceSelection() {
        guard NSWorkspace.shared.isVoiceOverEnabled, let item = selected, item.id != announcedID else { return }
        announcedID = item.id
        let section = sections.first { $0.rows.contains { $0.id == item.id } }?.title
        let words = [item.title, item.subtitle, section ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: words, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
