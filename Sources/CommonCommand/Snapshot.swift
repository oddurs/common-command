import AppKit

/// `CommonCommand --snapshot out.png [query] [--theme light|dark]` draws the panel with `query` typed into
/// an image and quits. It renders offscreen, so nothing appears on screen and nothing takes focus; glass
/// shows as a solid fill, since only the window server can draw it.
@MainActor
enum Snapshot {
    struct Request {
        var output: String
        var query: String
        var theme: Theme?
    }

    static func request(from arguments: [String]) -> Request? {
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return nil }
        var rest = Array(arguments[(index + 2)...])
        var theme: Theme?
        if let flag = rest.firstIndex(of: "--theme"), flag + 1 < rest.count {
            theme = Theme(rawValue: rest[flag + 1])
            rest.removeSubrange(flag...(flag + 1))
        }
        let query = rest.first { !$0.hasPrefix("--") } ?? ""
        return Request(output: arguments[index + 1], query: query, theme: theme)
    }

    static func run(_ request: Request, panel: PanelController, preferences: Preferences) {
        // Offscreen there's no glass, so draw the solid surfaces instead of nothing.
        preferences.translucent = false
        panel.model.query = request.query
        // Long enough for the app scan and the Spotlight file query to land.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated {
                panel.model.update(keepingSelection: true)
                let appearance = (request.theme ?? .system).appearance
                guard
                    let png = panel.renderOffscreen(appearance: appearance)?.representation(
                        using: .png, properties: [:])
                else {
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
}
