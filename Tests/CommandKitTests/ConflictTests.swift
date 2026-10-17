import Foundation
import Testing

@testable import CommandKit

@Suite struct ConflictTests {
    let commandSpace = KeyCombo(keyCode: 49, modifiers: .command)

    /// As `com.apple.symbolichotkeys` stores them on a Mac where Spotlight moved to ⌥⌘Space.
    let symbolic: [String: Any] = [
        "64": [
            "enabled": NSNumber(value: 1),
            "value": ["parameters": [32, 49, 1_572_864].map(NSNumber.init), "type": "standard"],
        ],
        "65": [
            "enabled": NSNumber(value: 0),
            "value": ["parameters": [32, 49, 1_048_576].map(NSNumber.init), "type": "standard"],
        ],
        "60": [
            "enabled": NSNumber(value: 1),
            "value": ["parameters": [32, 49, 262_144].map(NSNumber.init), "type": "standard"],
        ],
    ]

    @Test func readsSpotlightsEnabledShortcutsOnly() {
        let holders = Conflicts.spotlight(symbolic)
        #expect(holders.map(\.owner) == ["Spotlight"])
        #expect(holders.first?.combo == KeyCombo(keyCode: 49, modifiers: [.command, .option]))
    }

    @Test func readsAlfredsHotkey() {
        let prefs: [String: Any] = [
            "default": ["key": NSNumber(value: 49), "mod": NSNumber(value: 1_048_576), "string": " "]
        ]
        #expect(Conflicts.alfred(prefs)?.combo == commandSpace)
        #expect(Conflicts.alfred([:]) == nil)
    }

    @Test func findsAlfredsFileThroughItsPrefsJSON() {
        let json = #"{"current": "/Users/me/Dropbox/Alfred.alfredpreferences", "localhash": "abc123"}"#
        #expect(
            Conflicts.alfredHotkeyFile(prefsJSON: Data(json.utf8))?.path
                == "/Users/me/Dropbox/Alfred.alfredpreferences/preferences/local/abc123/hotkey/prefs.plist")
        #expect(Conflicts.alfredHotkeyFile(prefsJSON: Data("not json".utf8)) == nil)
    }

    @Test func namesWhoElseHoldsAShortcut() {
        let alfred = Conflicts.Holder(owner: "Alfred", combo: commandSpace, whereToChange: "Alfred")
        let holders = Conflicts.spotlight(symbolic) + [alfred]
        #expect(Conflicts.holder(of: commandSpace, among: holders)?.owner == "Alfred")
        #expect(
            Conflicts.holder(of: KeyCombo(keyCode: 49, modifiers: [.command, .option]), among: holders)?.owner
                == "Spotlight")
        #expect(Conflicts.holder(of: KeyCombo.standard, among: holders) == nil)
    }
}
