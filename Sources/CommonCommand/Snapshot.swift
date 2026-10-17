import AppKit
import CommandKit
import SwiftUI

/// `CommonCommand --snapshot out.png [query] [--theme light|dark] [--scope apps|files|actions] [--settings]` draws the panel with `query` typed into
/// an image and quits. It renders offscreen, so nothing appears on screen and nothing takes focus; glass
/// shows as a solid fill, since only the window server can draw it.
@MainActor
enum Snapshot {
    struct Request {
        var output: String
        var query: String
        var theme: Theme?
        var scope = Scope.all
        /// Draw the Settings window instead of the panel.
        var settings = false
    }

    static func request(from arguments: [String]) -> Request? {
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return nil }
        var rest = Array(arguments[(index + 2)...])
        var theme: Theme?
        if let flag = rest.firstIndex(of: "--theme"), flag + 1 < rest.count {
            theme = Theme(rawValue: rest[flag + 1])
            rest.removeSubrange(flag...(flag + 1))
        }
        var scope = Scope.all
        if let flag = rest.firstIndex(of: "--scope"), flag + 1 < rest.count {
            scope = Scope(rawValue: rest[flag + 1]) ?? .all
            rest.removeSubrange(flag...(flag + 1))
        }
        let settings = rest.contains("--settings")
        let query = rest.first { !$0.hasPrefix("--") } ?? ""
        return Request(output: arguments[index + 1], query: query, theme: theme, scope: scope, settings: settings)
    }

    static func run(_ request: Request, controller: AppController) {
        let panel = controller.panel
        let preferences = controller.preferences
        controller.refreshOtherShortcuts()
        // Offscreen there's no glass, so draw the solid surfaces instead of nothing.
        preferences.translucent = false
        panel.prepareForSnapshot()
        panel.model.scope = request.scope
        panel.model.query = request.query
        // Long enough for the app scan and the Spotlight file query to land.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated {
                panel.model.update(keepingSelection: true)
                let appearance = (request.theme ?? .system).appearance
                let image =
                    request.settings
                    ? renderSettings(controller, appearance: appearance) : panel.renderOffscreen(appearance: appearance)
                guard let png = image?.representation(using: .png, properties: [:]) else {
                    print("snapshot: couldn't render")
                    exit(1)
                }
                do {
                    try png.write(to: URL(filePath: request.output))
                    print("wrote \(request.output)")
                    exit(0)
                } catch {
                    print("snapshot: \(error.localizedDescription)")
                    exit(1)
                }
            }
        }
    }

    private static func renderSettings(_ controller: AppController, appearance: NSAppearance?) -> NSBitmapImageRep? {
        let view = NSHostingView(rootView: SettingsView(controller: controller, preferences: controller.preferences))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 720), styleMask: .borderless, backing: .buffered,
            defer: false)
        window.appearance = appearance
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }
}
