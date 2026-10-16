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

    @Test func findsPanesOnThisMac() {
        let panes = SettingsPanes.scan()
        #expect(panes.count > 10)
        #expect(panes.allSatisfy { $0.item.kind == .settings })
        #expect(Set(panes.map(\.item.title)).count == panes.count)
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
    @Test func theFieldAloneIsOneLine() {
        #expect(PanelSize.medium.height(rows: 0, visible: 8) == PanelSize.medium.fieldHeight)
    }

    @Test func growsWithResultsUntilItScrolls() {
        let size = PanelSize.medium
        #expect(size.height(rows: 3, visible: 8) < size.height(rows: 8, visible: 8))
        #expect(size.height(rows: 8, visible: 8) == size.height(rows: 20, visible: 8))
    }

    @Test func everySizeIsSmallerThanSpotlight() {
        // Spotlight on macOS 26 is about 680 points wide.
        #expect(PanelSize.allCases.allSatisfy { $0.width < 680 })
    }
}
