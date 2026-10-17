import Foundation
import Testing

@testable import CommandKit

@Suite struct ItemCommandTests {
    func item(_ kind: Kind, _ action: Action) -> Item {
        Item(id: "x", title: "x", subtitle: "", kind: kind, action: action)
    }

    @Test func filesCanBeShownPreviewedAndCopied() {
        let file = item(.file, .open(URL(filePath: "/Users/me/a.txt")))
        #expect(ItemCommand.commands(for: file, isRunning: false) == [.open, .showInFinder, .quickLook, .copyPath])
    }

    @Test func aRunningAppCanAlsoBeHiddenOrQuit() {
        let app = item(.application, .open(URL(filePath: "/Applications/Safari.app")))
        #expect(ItemCommand.commands(for: app, isRunning: false) == [.open, .showInFinder, .quickLook, .copyPath])
        #expect(ItemCommand.commands(for: app, isRunning: true).suffix(2) == [.hide, .quit])
    }

    @Test func aRunningFileIsNotAnApp() {
        let file = item(.file, .open(URL(filePath: "/Users/me/a.txt")))
        #expect(!ItemCommand.commands(for: file, isRunning: true).contains(.quit))
    }

    @Test func aLinkOrPaneCopiesItsAddress() {
        let link = item(.link, .open(URL(string: "https://github.com")!))
        #expect(ItemCommand.commands(for: link, isRunning: false) == [.open, .copyText("https://github.com")])
    }

    @Test func aCalculationOnlyCopies() {
        #expect(ItemCommand.commands(for: item(.calculation, .copy("4")), isRunning: false) == [.copyText("4")])
    }

    @Test func otherActionsOnlyRun() {
        #expect(ItemCommand.commands(for: item(.action, .shortcut("Arrive")), isRunning: false) == [.open])
    }

    @Test func menuShortcutsMatchThePanelsKeys() {
        #expect(ItemCommand.showInFinder.shortcut?.key == "\r" && ItemCommand.showInFinder.shortcut?.command == true)
        #expect(ItemCommand.quickLook.shortcut?.key == "y")
        #expect(ItemCommand.copyPath.shortcut?.shift == true)
    }
}
