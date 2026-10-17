import Foundation
import Testing

@testable import CommandKit

@Suite struct AppCatalogTests {
    func makeTree(_ paths: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "catalog-\(UUID().uuidString)")
        for path in paths {
            try FileManager.default.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
        }
        return root
    }

    @Test func findsAppsInFoldersButNotInsideApps() throws {
        let root = try makeTree([
            "Safari.app/Contents", "Utilities/Terminal.app", "Suite/Tools/Deep.app", "Suite/Tools/Deeper/Hidden.app",
            "Xcode.app/Contents/Applications/Instruments.app", "Notes.txt", ".Secret.app",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let names = Set(
            AppCatalog.scan(roots: [root], extras: []) { $0.deletingPathExtension().lastPathComponent }.map(
                \.item.title))
        #expect(names == ["Safari", "Terminal", "Deep", "Xcode"])
    }

    @Test func aSymlinkAndItsTargetAreOneApp() throws {
        let root = try makeTree(["Real/Safari.app"])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "Safari.app"), withDestinationURL: root.appending(path: "Real/Safari.app"))
        #expect(AppCatalog.scan(roots: [root], extras: []).count == 1)
    }

    @Test func theFileNameIsAnAlternativeToALocalisedName() throws {
        let root = try makeTree(["System Settings.app"])
        defer { try? FileManager.default.removeItem(at: root) }
        let candidate = try #require(AppCatalog.scan(roots: [root], extras: []) { _ in "Systemeinstellungen" }.first)
        #expect(candidate.names.map(\.string) == ["Systemeinstellungen", "System Settings"])
    }

    @Test func findsTheRealApplicationsFolder() {
        let titles = Set(AppCatalog.scan().map(\.item.title))
        #expect(titles.contains("Finder"))
        #expect(titles.contains("Safari"))
        #expect(titles.contains("Terminal"))
    }
}

@Suite struct SettingsPaneTests {
    @Test func prefersTheLocalisedName() {
        #expect(SettingsPanes.readableName(localized: "Menu Bar", raw: "ControlCenterSettings") == "Menu Bar")
    }

    @Test func dropsInternalNames() {
        #expect(SettingsPanes.readableName(localized: nil, raw: "PowerPreferences") == nil)
        #expect(SettingsPanes.readableName(localized: nil, raw: "HeadphoneSettingsExtension") == nil)
        #expect(SettingsPanes.readableName(localized: "", raw: nil) == nil)
    }

    @Test func keepsPlainNames() {
        #expect(SettingsPanes.readableName(localized: nil, raw: "Bluetooth") == "Bluetooth")
        #expect(SettingsPanes.readableName(localized: nil, raw: "VPN") == "VPN")
        #expect(SettingsPanes.readableName(localized: nil, raw: "Touch ID & Password") == "Touch ID & Password")
    }

    @Test func findsPanesAndTopicsOnThisMac() {
        let found = SettingsPanes.scan(isPortable: true)
        let panes = found.filter { !$0.item.id.contains("#") }
        #expect(panes.count > 10)
        #expect(found.count > panes.count)
        #expect(found.allSatisfy { $0.item.kind == .settings })
        #expect(Set(found.map(\.item.id)).count == found.count)
    }

    let terms: [String: Any] = [
        "Main": [
            "localizableStrings": [
                ["title": "Appearance", "index": "light, dark, theme, Dark Mode"],
                ["title": "Accent color", "index": "button, selection"],
                ["title": "Accent Color", "index": "duplicate"],
                ["title": "Low Power Mode", "index": "save battery", "portableOnly": true],
                ["title": "UPS", "index": "uninterruptible power", "desktopOnly": true],
                ["index": "no title"],
            ]
        ]
    ]
    let target = URL(string: "x-apple.systempreferences:com.apple.Appearance-Settings.extension")!

    @Test func topicsFollowWhetherTheMacHasABattery() {
        #expect(SettingsPanes.topics(in: terms, isPortable: true).map(\.title).contains("Low Power Mode"))
        #expect(!SettingsPanes.topics(in: terms, isPortable: true).map(\.title).contains("UPS"))
        #expect(SettingsPanes.topics(in: terms, isPortable: false).map(\.title).contains("UPS"))
        #expect(
            SettingsPanes.topics(in: terms, isPortable: true).first?.keywords == [
                "light", "dark", "theme", "Dark Mode",
            ])
    }

    @Test func aTopicNamedLikeItsPaneLendsThePaneItsKeywords() {
        let candidates = SettingsPanes.candidates(
            identifier: "appearance", name: "Appearance", topics: SettingsPanes.topics(in: terms, isPortable: true),
            target: target, icon: nil)
        #expect(candidates.map(\.item.title) == ["Appearance", "Accent color", "Low Power Mode"])
        #expect(candidates[0].item.subtitle == "")
        #expect(candidates[1].item.subtitle == "Appearance")
        #expect(candidates[1].weight < candidates[0].weight)
        #expect(Fuzzy.keywordScore(Fuzzy.prepare("dark"), candidates[0].keywords) != nil)
    }

    @Test func aPaneWithoutAReadableNameStillOffersItsTopics() {
        let candidates = SettingsPanes.candidates(
            identifier: "battery", name: nil,
            topics: [.init(title: "Battery", keywords: ["charge"]), .init(title: "Low Power Mode", keywords: [])],
            target: target, icon: nil)
        #expect(candidates.map(\.item.title) == ["Battery", "Low Power Mode"])
        #expect(candidates.allSatisfy { $0.item.subtitle == "" })
        #expect(candidates.allSatisfy { $0.matchesWordStarts })
    }
}

@Suite struct FileQueryTests {
    @Test func everyWordMustStartAWordInTheName() {
        #expect(
            FileQuery.spotlightQuery(for: " tax  2024 ")
                == #"kMDItemDisplayName == "tax*"cdw && kMDItemDisplayName == "2024*"cdw && kMDItemContentType != "com.apple.application-bundle""#
        )
    }

    @Test func escapesQuotesAndWildcards() {
        #expect(FileQuery.escape(#"a"b*c\d'e"#) == #"a\"b\*c\\d\'e"#)
    }

    @Test func emptyQueryRunsNothing() {
        #expect(FileQuery.spotlightQuery(for: "   ") == nil)
    }
}

@Suite struct KeyComboTests {
    @Test func displaysModifiersInTheSystemOrder() {
        let combo = KeyCombo(keyCode: 40, modifiers: [.command, .shift, .option, .control])
        #expect(combo.display { _ in "k" } == "⌃⌥⇧⌘K")
        #expect(KeyCombo.standard.display { _ in nil } == "⌥Space")
    }

    @Test func convertsToCarbonModifiers() {
        #expect(KeyCombo(keyCode: 49, modifiers: [.command, .option]).carbonModifiers == 0x0900)
        #expect(KeyCombo(keyCode: 49, modifiers: [.control, .shift]).carbonModifiers == 0x1200)
    }

    @Test func dropsFlagsThatArentModifiers() {
        #expect(KeyCombo(keyCode: 49, modifiers: .init(rawValue: 1 << 23 | 1 << 19)).modifiers == .option)
    }

    @Test func needsAModifierUnlessItsAFunctionKey() {
        #expect(!KeyCombo(keyCode: 49, modifiers: []).isUsable)
        #expect(!KeyCombo(keyCode: 0, modifiers: .shift).isUsable)
        #expect(KeyCombo(keyCode: 0, modifiers: .control).isUsable)
        #expect(KeyCombo(keyCode: 122, modifiers: []).isUsable)
    }

    @Test func roundTripsThroughJSON() throws {
        let combo = KeyCombo(keyCode: 49, modifiers: [.command])
        #expect(try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo)) == combo)
    }
}

@Suite struct LayoutTests {
    let size = PanelSize.medium

    @Test func theFieldAloneIsOneCapsule() {
        #expect(size.height(rows: 0, headers: 0, visible: 8) == size.fieldHeight)
        #expect(size.fieldRadius * 2 == size.fieldHeight)
    }

    @Test func theCardSitsBelowTheFieldWithAGap() {
        let card = size.cardHeight(rows: 2, headers: 1, visible: 8)
        #expect(size.height(rows: 2, headers: 1, visible: 8) == size.fieldHeight + size.gap + card)
        #expect(card == 2 * size.rowHeight + size.headerHeight + 2 * size.cardPadding)
    }

    @Test func growsWithResultsUntilItScrolls() {
        #expect(size.height(rows: 3, headers: 2, visible: 8) < size.height(rows: 8, headers: 2, visible: 8))
        #expect(size.height(rows: 9, headers: 3, visible: 8) == size.height(rows: 30, headers: 5, visible: 8))
    }

    @Test func theSelectionsCornersNestInTheCards() {
        #expect(PanelSize.allCases.allSatisfy { $0.rowRadius + $0.cardPadding == $0.cardRadius })
    }

    @Test func everySizeIsSmallerThanSpotlight() {
        // Spotlight on macOS 26 is about 680 points wide.
        #expect(PanelSize.allCases.allSatisfy { $0.width < 680 })
    }
}

@Suite struct FileResultsTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let home = "/Users/me"

    func found(_ path: String, folder: Bool = false, used: TimeInterval? = 0) -> FileResults.Found {
        FileResults.Found(path: path, isFolder: folder, lastUsed: used.map { now.addingTimeInterval(-$0) })
    }

    @Test func aFileSpotlightListsTwiceShowsOnce() {
        let results = FileResults.candidates(
            [found("/Users/me/Notes/calculators", folder: true), found("/Users/me/Notes/calculators", folder: true)],
            home: home, now: now)
        #expect(results.count == 1)
    }

    @Test func leavesOutClutter() {
        let results = FileResults.candidates(
            [
                found("/Users/me/Library/Caches/x.txt"), found("/Users/me/.config/x.txt"),
                found("/Users/me/code/app/target/doc/x.js"), found("/Users/me/code/web/node_modules/x/index.js"),
                found("/Users/me/Documents/x.txt"),
            ], home: home, now: now)
        #expect(results.map(\.item.title) == ["x.txt"])
        #expect(results.first?.item.subtitle == "~/Documents")
    }

    @Test func abbreviatesOnlyTheHomeFolderItself() {
        let results = FileResults.candidates(
            [found("/Users/me/a.txt"), found("/Users/me2/b.txt"), found("/Volumes/Disk/c.txt")], home: home, now: now)
        #expect(results.map(\.item.subtitle) == ["~", "/Users/me2", "/Volumes/Disk"])
    }

    @Test func recentlyUsedFilesRankHigherThanNeverOpenedOnes() {
        let results = FileResults.candidates(
            [
                found("/Users/me/week.txt", used: 3600), found("/Users/me/old.txt", used: 400 * 86400),
                found("/Users/me/generated.txt", used: nil),
            ], home: home, now: now)
        #expect(results.map(\.weight) == [8, 0, -12])
    }

    @Test func foldersAreFolders() {
        let results = FileResults.candidates([found("/Users/me/Projects", folder: true)], home: home, now: now)
        #expect(results.first?.item.kind == .folder)
        #expect(results.first?.item.fileURL?.hasDirectoryPath == true)
    }
}
