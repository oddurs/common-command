import Foundation
import Testing

@testable import CommandKit

@Suite struct ScopeTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let running = Actions.appActions([
        .init(name: "Safari", bundleIdentifier: "com.apple.Safari", url: URL(filePath: "/Applications/Safari.app")),
        .init(
            name: "Messages", bundleIdentifier: "com.apple.MobileSMS",
            url: URL(filePath: "/System/Applications/Messages.app")),
    ])
    let shortcuts = Actions.shortcuts(["Remind Me at Home", "Arrive", "Arrive"], icon: nil)

    func pane(_ title: String, topic: Bool = false) -> Candidate {
        Candidate(
            Item(
                id: "pane:" + title, title: title, subtitle: "", kind: .settings,
                action: .open(URL(string: "x-apple.systempreferences:x")!)),
            matchesWordStarts: topic)
    }

    func file(_ title: String) -> Candidate {
        Candidate(
            Item(
                id: "file:/x/" + title, title: title, subtitle: "~/x", kind: .file,
                action: .open(URL(filePath: "/x/" + title))))
    }

    func compose(_ query: String, scope: Scope, _ candidates: [Candidate], files: [Candidate] = []) -> [ResultSection] {
        var options = SearchOptions()
        options.scope = scope
        options.locale = Locale(identifier: "en_US")
        return Results.compose(
            query: query, candidates: candidates, files: files, usage: Usage(), now: now, options: options)
    }

    var everything: [Candidate] { [app("Safari"), app("Slack"), pane("Sound")] + running + shortcuts }

    @Test func aScopeShowsOnlyItsKind() {
        #expect(
            compose("s", scope: .apps, everything, files: [file("safari.txt")]).rows.allSatisfy {
                [.application, .settings, .command].contains($0.item.kind)
            })
        #expect(
            compose("s", scope: .files, everything, files: [file("safari.txt")]).rows.map(\.item.title) == [
                "safari.txt"
            ])
        #expect(compose("a", scope: .actions, everything).rows.allSatisfy { $0.item.kind == .action })
    }

    @Test func aScopeLeavesOutCalculationsAndTheWeb() {
        let kinds = compose("2+2", scope: .apps, everything).rows.map(\.item.kind)
        #expect(!kinds.contains(.calculation) && !kinds.contains(.webSearch))
    }

    @Test func nothingTypedInEverythingShowsNothing() {
        #expect(compose("", scope: .all, everything).isEmpty)
    }

    @Test func nothingTypedInAppsListsAppsAndPanesFromAToZ() {
        let sections = compose("", scope: .apps, everything + [app("Notes"), pane("Low Power Mode", topic: true)])
        #expect(sections.map(\.title) == ["Applications", "System Settings"])
        #expect(sections[0].rows.map(\.item.title) == ["Notes", "Safari", "Slack"])
        // Topics would bury the panes.
        #expect(sections[1].rows.map(\.item.title) == ["Sound"])
    }

    @Test func nothingTypedInFilesKeepsTheOrderGiven() {
        let sections = compose("", scope: .files, everything, files: [file("b.txt"), file("a.txt")])
        #expect(sections.map(\.title) == ["Recent Files"])
        #expect(sections.rows.map(\.item.title) == ["b.txt", "a.txt"])
    }

    @Test func nothingTypedInActionsListsShortcutsThenEachAppsActionsTogether() {
        let sections = compose("", scope: .actions, everything)
        #expect(sections.map(\.title) == ["Shortcuts", "Running Apps"])
        #expect(sections[0].rows.map(\.item.title) == ["Arrive", "Remind Me at Home"])
        #expect(sections[1].rows.map(\.item.title) == ["Quit Messages", "Hide Messages", "Quit Safari", "Hide Safari"])
    }

    @Test func anEmptyScopeShowsNoSections() {
        #expect(compose("", scope: .actions, [app("Safari")]).isEmpty)
    }

    @Test func scopesHaveSpotlightsKeys() {
        #expect(Scope.scoped.map(\.key) == ["1", "2", "3"])
        #expect(Scope.all.key == nil)
    }
}

@Suite struct ActionsTests {
    @Test func readsTheShortcutsList() {
        #expect(
            Actions.shortcutNames(fromList: "New Shortcut\n  Arrive \n\nRemind Me at Home\n") == [
                "New Shortcut", "Arrive", "Remind Me at Home",
            ])
    }

    @Test func aShortcutListedTwiceShowsOnce() {
        #expect(Actions.shortcuts(["Arrive", "Arrive"], icon: nil).count == 1)
    }

    @Test func shortcutsRunByName() {
        #expect(Actions.shortcuts(["Arrive"], icon: nil).first?.item.action == .shortcut("Arrive"))
    }

    @Test func quitAndHideMatchByWordStartsOnly() {
        let actions = Actions.appActions([
            .init(name: "Messages", bundleIdentifier: "m", url: URL(filePath: "/m.app")),
            .init(name: "Safari", bundleIdentifier: "s", url: URL(filePath: "/s.app")),
        ])
        let ranked = Ranker.rank(actions, query: "quit sa", usage: Usage(), now: Date(), limit: 5)
        #expect(ranked.map(\.item.title) == ["Quit Safari"])
        #expect(ranked.first?.item.action == .quit("s"))
    }

    @Test func actionsRankBelowAnAppWithTheSameName() {
        let actions = Actions.shortcuts(["Safari Reading List"], icon: nil)
        let ranked = Ranker.rank(actions + [app("Safari")], query: "safari", usage: Usage(), now: Date(), limit: 2)
        #expect(ranked.first?.item.kind == .application)
    }
}
