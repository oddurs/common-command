import AppKit

/// `CommonCommand --snapshot out.png [query] [--theme light|dark]` opens the real panel with `query` typed,
/// captures it over whatever is behind it, and quits. For reviewing design changes. Capturing the
/// desktop behind the panel needs Screen Recording access for the terminal running it.
@MainActor
enum Snapshot {
    struct Request {
        var output: String
        var query: String
        var theme: Theme?
    }

    static func request(from arguments: [String]) -> Request? {
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return nil }
        let rest = Array(arguments[(index + 2)...])
        var theme: Theme?
        if let flag = rest.firstIndex(of: "--theme"), flag + 1 < rest.count { theme = Theme(rawValue: rest[flag + 1]) }
        let query = rest.first { !$0.hasPrefix("--") && Theme(rawValue: $0) == nil } ?? ""
        return Request(output: arguments[index + 1], query: query, theme: theme)
    }

    static func run(_ request: Request, panel: PanelController, preferences: Preferences) {
        if let theme = request.theme { preferences.theme = theme }
        panel.show()
        panel.model.query = request.query
        // Long enough for the Spotlight file query and the first icon loads to land.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated {
                let capture = Process()
                capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
                // A margin around the frame, so the shadow and the glass's edge show.
                let frame = panel.frame.insetBy(dx: -24, dy: -24)
                let top = (NSScreen.screens.first?.frame.maxY ?? 0) - frame.maxY
                let region = "\(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))"
                capture.arguments = ["-x", "-R\(region)", request.output]
                do {
                    try capture.run()
                    capture.waitUntilExit()
                    print("wrote \(request.output)")
                    exit(capture.terminationStatus)
                } catch {
                    print("screencapture failed: \(error.localizedDescription)")
                    exit(1)
                }
            }
        }
    }
}
