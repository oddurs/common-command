import AppKit
import CommandKit

/// Wires the shortcut, the panel, the menu bar item, and Settings together, and carries out what a
/// result does when chosen.
@MainActor
final class AppController: NSObject {
    private static let onboardedKey = "onboarded"

    let preferences: Preferences
    private let library = Library()
    private let hotKey = HotKey()
    private(set) lazy var panel = PanelController(preferences: preferences, library: library)
    private lazy var settings = SettingsWindow(controller: self)
    private var statusItem: NSStatusItem?
    private(set) var hotKeyProblem: String?
    /// Spotlight's and Alfred's shortcuts, read when the shortcut is set and when Settings opens.
    private(set) var otherShortcuts: [Conflicts.Holder] = []

    /// Another app that also answers to our shortcut. macOS accepts both without complaint, and then only
    /// one of them opens.
    var hotKeyConflict: Conflicts.Holder? {
        Conflicts.holder(of: preferences.hotKey, among: otherShortcuts)
    }

    init(snapshot: Snapshot.Request? = nil) {
        // A snapshot mustn't change the real settings.
        preferences = snapshot == nil ? Preferences() : Preferences(defaults: UserDefaults(suiteName: "snapshot")!)
        super.init()
        library.commands = [
            Candidate(
                Item(
                    id: "command:settings", title: "Common Command Settings", subtitle: "", kind: .command,
                    action: .command("settings")), alternatives: ["Preferences"]),
            Candidate(
                Item(
                    id: "command:quit", title: "Quit Common Command", subtitle: "", kind: .command,
                    action: .command("quit"))),
        ]
        library.refreshIfStale()
        panel.perform = { [weak self] item, reveal in self?.perform(item, reveal: reveal) }
        hotKey.onPress = { [weak self] in self?.panel.toggle() }
        if let snapshot {
            Snapshot.run(snapshot, controller: self)
            return
        }
        registerHotKey()
        updateStatusItem()

        if !UserDefaults.standard.bool(forKey: Self.onboardedKey) {
            UserDefaults.standard.set(true, forKey: Self.onboardedKey)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.showSettings() }
            }
        }
    }

    // MARK: Shortcut

    func refreshOtherShortcuts() {
        otherShortcuts = otherAppsShortcuts()
    }

    func registerHotKey() {
        refreshOtherShortcuts()
        do {
            try hotKey.register(preferences.hotKey)
            hotKeyProblem = nil
        } catch {
            hotKeyProblem = error.localizedDescription
        }
        updateStatusItem()
    }

    /// While a new shortcut is being recorded, the old one mustn't fire.
    func suspendHotKey() {
        hotKey.unregister()
    }

    // MARK: Settings

    @objc func showSettings() {
        // Spotlight's or Alfred's shortcut may have changed since; the warning in Settings should be current.
        refreshOtherShortcuts()
        panel.hide()
        settings.show()
    }

    @objc func showPanel() {
        panel.show()
    }

    func preferencesChanged() {
        updateStatusItem()
        panel.preferencesChanged()
    }

    // MARK: Menu bar

    private func updateStatusItem() {
        guard preferences.showsMenuBarItem else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.autosaveName = "command"
        item.button?.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Common Command")

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Common Command", action: #selector(showPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        if let conflict = hotKeyConflict {
            let problem = NSMenuItem(
                title: "\(preferences.hotKey.displayName) also opens \(conflict.owner)",
                action: #selector(showSettings),
                keyEquivalent: "")
            problem.target = self
            menu.addItem(problem)
        } else if let hotKeyProblem {
            let problem = NSMenuItem(title: hotKeyProblem, action: nil, keyEquivalent: "")
            problem.isEnabled = false
            menu.addItem(problem)
        } else {
            let shortcut = NSMenuItem(
                title: "Shortcut: \(preferences.hotKey.displayName)", action: nil, keyEquivalent: "")
            shortcut.isEnabled = false
            menu.addItem(shortcut)
        }
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Common Command", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )
        item.menu = menu
    }

    // MARK: Actions

    private func perform(_ item: Item, reveal: Bool) {
        switch item.action {
        case .open(let url):
            if reveal, url.isFileURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else if item.kind == .application {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) {
                    _, error in
                    guard let error else { return }
                    DispatchQueue.main.async { Self.present(error) }
                }
            } else if !NSWorkspace.shared.open(url) {
                Self.present(CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: url]))
            }
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .command("settings"):
            showSettings()
        case .command("quit"):
            NSApp.terminate(nil)
        case .command:
            break
        case .shortcut(let name):
            runShortcut(name)
        case .quit(let id):
            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
        case .hide(let id):
            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.hide() }
        }
    }

    /// Runs a shortcut through the `shortcuts` tool, off the main thread: some take a while, and the panel
    /// is already closed. A failure is reported, since nothing else would show it.
    private func runShortcut(_ name: String) {
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]
            let errors = Pipe()
            process.standardError = errors
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                await MainActor.run { Self.present(error) }
                return
            }
            guard process.terminationStatus != 0 else { return }
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            await MainActor.run {
                Self.present(
                    CocoaError(
                        .featureUnsupported,
                        userInfo: [
                            NSLocalizedDescriptionKey: "The shortcut “\(name)” didn't finish.",
                            NSLocalizedRecoverySuggestionErrorKey: message.trimmingCharacters(
                                in: .whitespacesAndNewlines),
                        ]))
            }
        }
    }

    private static func present(_ error: Error) {
        NSApp.activate()
        NSAlert(error: error).runModal()
    }
}

extension AppController: NSApplicationDelegate {
    /// Opening the app again while it runs is how people look for its settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
}
