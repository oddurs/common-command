import CommandKit
import Foundation

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
    private(set) var results: [Ranked] = []
    var selection = 0
    /// True while ⌘ is held, so each row shows its ⌘1–⌘9 shortcut.
    var showsShortcuts = false
    /// Whether the pointer has really moved since the last key. Rows change under a still pointer while
    /// you type, and that mustn't take the selection, or Return would open whatever happened to land there.
    @ObservationIgnored var pointerMoved = false

    @ObservationIgnored var onResultsChange: (() -> Void)?
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
        guard preferences.searchesFiles, !text.isEmpty else {
            files = []
            return
        }
        fileTask = Task {
            try? await Task.sleep(for: Self.fileDelay)
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) { FileSearch.run(text) }.value
            guard !Task.isCancelled else { return }
            files = found
            compose(keepingSelection: true)
        }
    }

    private func compose(keepingSelection: Bool) {
        let selectedID = keepingSelection && selection != 0 ? selected?.id : nil
        // Files from the previous keystroke stay until the new ones arrive; ranking drops those that no
        // longer match, so the list doesn't flicker.
        results = Results.compose(
            query: query, candidates: library.candidates(includingPanes: preferences.searchesSettings),
            files: preferences.searchesFiles ? files : [], usage: library.usage, now: Date(),
            options: preferences.searchOptions)
        if let selectedID, let index = results.firstIndex(where: { $0.id == selectedID }) {
            selection = index
        } else {
            selection = 0
        }
        onResultsChange?()
    }
}
