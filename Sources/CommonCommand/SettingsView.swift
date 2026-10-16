import AppKit
import CommandKit
import SwiftUI

/// Laid out by the Common Tools Settings standard: the app's own sections, then General, then
/// `CommonToolsSection`, so every app's Settings window reads the same.
struct SettingsView: View {
    let controller: AppController
    @Bindable var preferences: Preferences
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    private static let keyboardShortcuts = URL(
        string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

    var body: some View {
        Form {
            Section {
                LabeledContent("Open Common Command") {
                    ShortcutRecorder(controller: controller, combo: $preferences.hotKey)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let problem = controller.hotKeyProblem {
                        Text(problem).foregroundStyle(.red)
                    }
                    Text("To use ⌘Space, first turn off Spotlight's shortcut in Keyboard Shortcuts.")
                        .foregroundStyle(.secondary)
                    Button("Open Keyboard Shortcuts…") { NSWorkspace.shared.open(Self.keyboardShortcuts) }
                        .buttonStyle(.link)
                }
                .font(.callout)
            }

            Section("Appearance") {
                Picker("Theme", selection: $preferences.theme) {
                    Text("System").tag(Theme.system)
                    Text("Light").tag(Theme.light)
                    Text("Dark").tag(Theme.dark)
                }
                .pickerStyle(.segmented)
                Picker("Size", selection: $preferences.size) {
                    Text("Small").tag(PanelSize.small)
                    Text("Medium").tag(PanelSize.medium)
                    Text("Large").tag(PanelSize.large)
                }
                .pickerStyle(.segmented)
                Toggle("Translucent", isOn: $preferences.translucent)
                LabeledContent("Results shown") {
                    Stepper(value: $preferences.visibleRows, in: Preferences.visibleRowsRange) {
                        Text("\(preferences.visibleRows)").monospacedDigit()
                    }
                }
            }

            Section {
                Toggle("System Settings", isOn: $preferences.searchesSettings)
                Toggle("Files and folders", isOn: $preferences.searchesFiles)
                Toggle("Calculator", isOn: $preferences.calculates)
                Toggle("Web search", isOn: $preferences.searchesWeb)
                Picker("Search engine", selection: $preferences.engine) {
                    ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
                }
                .disabled(!preferences.searchesWeb)
            } header: {
                Text("Search")
            } footer: {
                Text("Apps are always searched. Files come from the Spotlight index of your home folder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show in menu bar", isOn: $preferences.showsMenuBarItem)
                Toggle("Open at login", isOn: $openAtLogin)
            } header: {
                Text("General")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !preferences.showsMenuBarItem {
                        Text("Open Common Command from Finder again to get back to Settings.")
                    }
                    if let loginError { Text(loginError) }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            CommonToolsSection()
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 720)
        .onChange(of: preferences.theme) { controller.preferencesChanged() }
        .onChange(of: preferences.size) { controller.preferencesChanged() }
        .onChange(of: preferences.translucent) { controller.preferencesChanged() }
        .onChange(of: preferences.showsMenuBarItem) { controller.preferencesChanged() }
        .onChange(of: openAtLogin) { _, enabled in
            guard enabled != LoginItem.isEnabled else { return }
            do {
                try LoginItem.setEnabled(enabled)
                loginError = nil
            } catch {
                loginError = error.localizedDescription
                openAtLogin = LoginItem.isEnabled
            }
        }
    }
}

/// Click, then press the new shortcut. Escape cancels, Delete restores the default.
struct ShortcutRecorder: View {
    let controller: AppController
    @Binding var combo: KeyCombo
    @State private var recording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 8) {
            if let hint { Text(hint).font(.callout).foregroundStyle(.secondary) }
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type Shortcut…" : combo.displayName)
                    .monospacedDigit()
                    .frame(minWidth: 110)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        controller.suspendHotKey()
        recording = true
        hint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            MainActor.assumeIsolated { record(keyCode: keyCode, flags: flags) }
            // Swallowed, so the key doesn't also reach the Settings window.
            return nil
        }
    }

    private func record(keyCode: UInt16, flags: UInt) {
        switch keyCode {
        case 53:  // Escape
            stop()
        case 51, 117:  // Delete, Forward Delete
            combo = .standard
            stop()
        default:
            let candidate = KeyCombo(keyCode: keyCode, modifiers: KeyCombo.Modifiers(rawValue: flags))
            guard candidate.isUsable else {
                hint = "Add ⌘, ⌥, or ⌃"
                return
            }
            combo = candidate
            stop()
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        hint = nil
        controller.registerHotKey()
    }
}
