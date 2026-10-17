import Foundation
import Testing

@testable import CommandKit

func app(_ title: String, alternatives: [String] = [], weight: Int = AppCatalog.weight) -> Candidate {
    Candidate(
        Item(
            id: "app:" + title, title: title, subtitle: "Application", kind: .application,
            action: .open(URL(filePath: "/Applications/\(title).app"))),
        alternatives: alternatives, weight: weight)
}

func titles(_ ranked: [Ranked]) -> [String] { ranked.map(\.item.title) }

@Suite struct FuzzyTests {
    func score(_ query: String, _ name: String) -> Int? { Fuzzy.match(query, in: SearchText(name))?.score }

    @Test func everyQueryCharacterMustAppearInOrder() {
        #expect(score("saf", "Safari") != nil)
        #expect(score("fas", "Safari") == nil)
        #expect(score("safarix", "Safari") == nil)
        #expect(score("", "Safari") == nil)
    }

    @Test func foldsCaseAndAccents() {
        #expect(score("CAFE", "Café") != nil)
        #expect(score("über", "Uber Driver") != nil)
    }

    @Test func wordStartsBeatTheSameLettersMidWord() throws {
        let initials = try #require(score("vsc", "Visual Studio Code"))
        let scattered = try #require(score("vsc", "Advisor Script"))
        #expect(initials > scattered)
    }

    @Test func aPrefixBeatsAMatchFurtherIn() throws {
        #expect(try #require(score("note", "Notes")) > #require(score("note", "Sticky Notes")))
    }

    @Test func anExactNameBeatsALongerOne() throws {
        #expect(try #require(score("mail", "Mail")) > #require(score("mail", "Mailspring")))
    }

    @Test func consecutiveLettersBeatScatteredOnes() throws {
        #expect(try #require(score("term", "Terminal")) > #require(score("term", "Text Edit Remote Mirror")))
    }

    @Test func positionsPointAtTheCharactersThatMatched() {
        #expect(Fuzzy.match("vsc", in: SearchText("Visual Studio Code"))?.positions == [0, 7, 14])
        #expect(Fuzzy.match("sys set", in: SearchText("System Settings"))?.positions == [0, 1, 2, 7, 8, 9])
    }

    @Test func positionsCountCharactersNotBytes() {
        #expect(Fuzzy.match("fe", in: SearchText("Café Feed"))?.positions == [5, 6])
        #expect(Fuzzy.match("ab", in: SearchText("👾 Abc"))?.positions == [2, 3])
    }

    @Test func spacesInTheQueryAreIgnored() {
        #expect(score("system settings", "System Settings") != nil)
    }
}

@Suite struct RankerTests {
    let apps = [
        app("Safari"), app("Slack"), app("System Settings"), app("Visual Studio Code"), app("Sublime Text"),
        app("Messages"), app("Mail"), app("Music"),
    ]
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func bestMatchComesFirst() {
        let ranked = Ranker.rank(apps, query: "vsc", usage: Usage(), now: now, limit: 3)
        #expect(ranked.first?.item.title == "Visual Studio Code")
        #expect(ranked.first?.highlights == [0, 7, 14])
    }

    @Test func respectsTheLimit() {
        #expect(Ranker.rank(apps, query: "s", usage: Usage(), now: now, limit: 2).count == 2)
        #expect(Ranker.rank(apps, query: "s", usage: Usage(), now: now, limit: 0).isEmpty)
    }

    @Test func tiesGoToTheShorterName() {
        #expect(
            titles(Ranker.rank(apps, query: "m", usage: Usage(), now: now, limit: 3)) == ["Mail", "Music", "Messages"])
    }

    @Test func choosingSomethingForAQueryPutsItFirstNextTime() {
        #expect(Ranker.rank(apps, query: "s", usage: Usage(), now: now, limit: 1).first?.item.title == "Slack")
        var usage = Usage()
        usage.record("app:Sublime Text", query: "s", at: now)
        #expect(Ranker.rank(apps, query: "s", usage: usage, now: now, limit: 1).first?.item.title == "Sublime Text")
        // Another query is untouched apart from the frecency nudge.
        #expect(Ranker.rank(apps, query: "saf", usage: usage, now: now, limit: 1).first?.item.title == "Safari")
    }

    @Test func aChoiceForALongerQueryLeansAShorterOneTheSameWay() {
        var usage = Usage()
        // Equally frequent, so only the remembered query can separate them.
        usage.record("app:Safari", query: "", at: now)
        usage.record("app:Sublime Text", query: "sublime", at: now)
        #expect(Ranker.rank(apps, query: "s", usage: usage, now: now, limit: 1).first?.item.title == "Sublime Text")
    }

    @Test func alternativeNamesMatchWithoutHighlighting() {
        let localised = [app("Systemeinstellungen", alternatives: ["System Settings"])]
        let ranked = Ranker.rank(localised, query: "system set", usage: Usage(), now: now, limit: 1)
        #expect(ranked.first?.item.title == "Systemeinstellungen")
        #expect(ranked.first?.highlights == [])
    }

    @Test func weightBreaksAnEvenMatchInFavourOfApps() {
        let pane = Candidate(
            Item(
                id: "pane:display", title: "Displays", subtitle: "System Settings", kind: .settings,
                action: .open(URL(string: "x-apple.systempreferences:x")!)))
        let ranked = Ranker.rank([pane, app("Displays")], query: "displays", usage: Usage(), now: now, limit: 2)
        #expect(ranked.map(\.item.kind) == [.application, .settings])
    }

    @Test func aMuchCloserNameBeatsTheAppWeight() {
        let pane = Candidate(
            Item(
                id: "pane:bt", title: "Bluetooth", subtitle: "System Settings", kind: .settings,
                action: .open(URL(string: "x-apple.systempreferences:x")!)))
        let ranked = Ranker.rank(
            [app("Bluetooth File Exchange"), pane], query: "blue", usage: Usage(), now: now, limit: 2)
        #expect(ranked.first?.item.kind == .settings)
    }
}

@Suite struct WordStartTests {
    func topic(_ title: String) -> Candidate {
        Candidate(
            Item(
                id: "pane:x#" + title, title: title, subtitle: "", kind: .settings,
                action: .open(URL(string: "x-apple.systempreferences:x")!)),
            weight: SettingsPanes.topicWeight, matchesWordStarts: true)
    }

    func ranks(_ query: String, _ title: String) -> Bool {
        !Ranker.rank([topic(title)], query: query, usage: Usage(), now: Date(), limit: 1).isEmpty
    }

    @Test func eachWordMustStartAWordInOrder() {
        #expect(ranks("low power", "Low Power Mode"))
        #expect(ranks("power", "Low Power Mode"))
        #expect(ranks("low pow", "Low Power Mode"))
        #expect(!ranks("power low", "Low Power Mode"))
    }

    @Test func initialsAndScatteredLettersDontMatch() {
        #expect(!ranks("saf", "Screen area for display"))
        #expect(!ranks("lpm", "Low Power Mode"))
        #expect(!ranks("ower", "Low Power Mode"))
    }

    @Test func highlightsTheMatchedWordStarts() {
        let ranked = Ranker.rank([topic("Low Power Mode")], query: "low pow", usage: Usage(), now: Date(), limit: 1)
        #expect(ranked.first?.highlights == [0, 1, 2, 4, 5, 6])
    }

    @Test func appsStillMatchByInitials() {
        #expect(!Ranker.rank([app("Visual Studio Code")], query: "vsc", usage: Usage(), now: Date(), limit: 1).isEmpty)
    }
}

@Suite struct KeywordTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func pane(_ title: String, keywords: [String] = [], weight: Int = 0) -> Candidate {
        Candidate(
            Item(
                id: "pane:" + title, title: title, subtitle: "System Settings", kind: .settings,
                action: .open(URL(string: "x-apple.systempreferences:x")!)),
            keywords: keywords, weight: weight)
    }

    @Test func aKeywordFindsWhatTheNameDoesNot() {
        let ranked = Ranker.rank(
            [pane("Appearance", keywords: ["theme", "Dark Mode"]), app("Darkroom")], query: "dark mode", usage: Usage(),
            now: now, limit: 2)
        #expect(ranked.map(\.item.title) == ["Appearance"])
        #expect(ranked.first?.highlights == [])
    }

    @Test func everyWordOfAKeywordCounts() {
        let ranked = Ranker.rank(
            [pane("Appearance", keywords: ["Dark Mode"])], query: "mode", usage: Usage(), now: now, limit: 1)
        #expect(ranked.count == 1)
    }

    @Test func shortQueriesDontReachKeywords() {
        // Three letters are an app's name far more often than a settings keyword.
        #expect(
            Ranker.rank([pane("Lockdown Mode", keywords: ["safety"])], query: "saf", usage: Usage(), now: now, limit: 1)
                .isEmpty)
        #expect(
            !Ranker.rank(
                [pane("Lockdown Mode", keywords: ["safety"])], query: "safe", usage: Usage(), now: now, limit: 1
            ).isEmpty)
    }

    @Test func keywordsMatchFromTheirStartOnly() {
        #expect(
            Ranker.rank([pane("Appearance", keywords: ["theme"])], query: "eme", usage: Usage(), now: now, limit: 1)
                .isEmpty)
    }

    @Test func aNameStartingWithTheQueryBeatsAKeyword() {
        let ranked = Ranker.rank(
            [pane("Appearance", keywords: ["display"]), pane("Displays")], query: "disp", usage: Usage(), now: now,
            limit: 2)
        #expect(ranked.map(\.item.title) == ["Displays", "Appearance"])
    }

    @Test func topicsStayBelowAppsTheyMerelyResemble() {
        let topic = pane("Set time zone", weight: SettingsPanes.topicWeight)
        let ranked = Ranker.rank([topic, app("System Settings")], query: "set", usage: Usage(), now: now, limit: 2)
        #expect(ranked.first?.item.title == "System Settings")
    }

    @Test func anAppBeatsASettingOnATie() {
        let ranked = Ranker.rank(
            [pane("Game Center"), app("Google Chrome")], query: "gc", usage: Usage(), now: now, limit: 2)
        #expect(ranked.first?.item.title == "Google Chrome")
    }
}

@Suite struct UsageTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func recentUseBoostsMoreThanOldUse() {
        var usage = Usage()
        usage.record("a", query: "x", at: now)
        let fresh = usage.boost(for: "a", query: "other", at: now)
        let stale = usage.boost(for: "a", query: "other", at: now.addingTimeInterval(60 * 24 * 3600))
        #expect(fresh > stale)
        #expect(stale >= 0)
    }

    @Test func frecencyIsCapped() {
        var usage = Usage()
        for _ in 0..<10_000 { usage.record("a", query: "", at: now) }
        #expect(usage.boost(for: "a", query: "", at: now) == Usage.maximumFrecencyBoost)
    }

    @Test func choicesMatchTheFoldedQuery() {
        var usage = Usage()
        usage.record("a", query: "Café ", at: now)
        #expect(usage.boost(for: "a", query: "cafe", at: now) >= Usage.choiceBoost)
    }

    @Test func sharedStartsEarnAShareOfTheBoost() {
        var usage = Usage()
        usage.record("safari", query: "safari", at: now)
        usage.record("saf-tool", query: "saf", at: now)
        usage.record("slack", query: "sl", at: now)
        #expect(usage.choiceBoosts("safari") == ["safari": 120, "saf-tool": 30])
        #expect(usage.choiceBoosts("sa") == ["safari": 20, "saf-tool": 40])
        #expect(usage.choiceBoosts("safar") == ["safari": 50, "saf-tool": 36])
        #expect(usage.choiceBoosts("s") == ["safari": 10, "saf-tool": 20, "slack": 30])
        #expect(usage.choiceBoosts("x").isEmpty)
        #expect(usage.choiceBoosts("").isEmpty)
    }

    @Test func anItemChosenForSeveralQueriesTakesTheBestBoost() {
        var usage = Usage()
        usage.record("safari", query: "sa", at: now)
        usage.record("safari", query: "safari", at: now)
        #expect(usage.choiceBoosts("saf") == ["safari": 40])
    }

    @Test func storageStaysBounded() {
        var usage = Usage()
        for i in 0..<(Usage.maximumEntries + 50) { usage.record("id\(i)", query: "q\(i)", at: now) }
        #expect(usage.entries.count == Usage.maximumEntries)
    }

    @Test func roundTripsThroughJSON() throws {
        var usage = Usage()
        usage.record("a", query: "q", at: now)
        let decoded = try JSONDecoder().decode(Usage.self, from: JSONEncoder().encode(usage))
        #expect(decoded == usage)
    }
}

@Suite struct ResultsTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    var options: SearchOptions {
        var options = SearchOptions()
        options.locale = Locale(identifier: "en_US")
        return options
    }

    func compose(
        _ query: String, _ candidates: [Candidate] = [], files: [Candidate] = [], options: SearchOptions? = nil
    )
        -> [ResultSection]
    {
        Results.compose(
            query: query, candidates: candidates, files: files, usage: Usage(), now: now,
            options: options ?? self.options)
    }

    func file(_ title: String, weight: Int = 0) -> Candidate {
        Candidate(
            Item(
                id: "file:/x/" + title, title: title, subtitle: "~/x", kind: .file,
                action: .open(URL(filePath: "/x/" + title))),
            weight: weight)
    }

    @Test func emptyQueryShowsNothing() {
        #expect(compose("  ", [app("Safari")]).isEmpty)
    }

    @Test func calculationComesFirstAndWebSearchLast() {
        let sections = compose("2+2", [app("2+2 Game")])
        #expect(sections.map(\.title) == ["Calculator", "Top Hit", "Search the Web"])
        #expect(sections.rows.map(\.item.kind) == [.calculation, .application, .webSearch])
        #expect(sections.rows.first?.item.title == "4")
        #expect(sections.rows.first?.item.action == .copy("4"))
    }

    @Test func copiedResultHasNoGroupingSeparator() {
        let rows = compose("1000*1000").rows
        #expect(rows.first?.item.title == "1,000,000")
        #expect(rows.first?.item.action == .copy("1000000"))
    }

    @Test func theBestMatchIsTheTopHitAndTheRestGroupByKind() {
        let pane = Candidate(
            Item(
                id: "pane:notes", title: "Notes settings", subtitle: "", kind: .settings,
                action: .open(URL(string: "x-apple.systempreferences:x")!)))
        let sections = compose("notes", [app("Notes"), app("Notesnook"), pane], files: [file("notes.txt", weight: 8)])
        #expect(sections.map(\.title) == ["Top Hit", "Files", "Applications", "System Settings", "Search the Web"])
        #expect(sections[0].rows.map(\.item.title) == ["Notes"])
        #expect(sections.rows.count == 5)
    }

    @Test func groupsFollowTheirBestMember() {
        // The file outscores the second app, so Files comes before Applications.
        let merged = Results.merge(
            [Ranked(item: app("A").item, score: 90), Ranked(item: app("B").item, score: 40)],
            [Ranked(item: file("c").item, score: 60)])
        #expect(merged.map(\.score) == [90, 60, 40])
        #expect(Results.group(merged).map(\.title) == ["Top Hit", "Files", "Applications"])
    }

    @Test func aTieKeepsTheAppFirst() {
        let merged = Results.merge([Ranked(item: app("A").item, score: 50)], [Ranked(item: file("b").item, score: 50)])
        #expect(merged.map(\.item.kind) == [.application, .file])
    }

    @Test func turningSourcesOffRemovesThem() {
        var options = options
        options.calculator = false
        options.webSearch = false
        #expect(compose("2+2", options: options).isEmpty)
    }

    @Test func anAddressOpensAsALink() {
        let sections = compose("github.com")
        #expect(sections.first?.title == "Website")
        #expect(sections.rows.first?.item.action == .open(URL(string: "https://github.com")!))
    }
}
