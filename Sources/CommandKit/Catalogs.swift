import Foundation

/// Finds installed apps by walking the folders apps live in. No index, no Spotlight query: a few hundred
/// directory entries, read in a few milliseconds, so the list is never stale for long.
public enum AppCatalog {
    public static var standardRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            "/Applications", "/System/Applications", "/System/Library/CoreServices/Applications",
            home.appending(path: "Applications").path,
        ].map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// Apps that live outside the usual folders but people expect to find.
    public static let extras = [URL(filePath: "/System/Library/CoreServices/Finder.app")]

    /// Folders inside a root are searched this deep, for /Applications/Utilities and suites like
    /// /Applications/Adobe Photoshop/.
    static let depth = 2

    public static func scan(
        roots: [URL] = standardRoots, extras: [URL] = extras, displayName: (URL) -> String = defaultDisplayName
    ) -> [Candidate] {
        var seen: Set<String> = []
        var candidates: [Candidate] = []
        func add(_ url: URL) {
            let resolved = url.resolvingSymlinksInPath().path
            guard seen.insert(resolved).inserted else { return }
            let fileName = url.deletingPathExtension().lastPathComponent
            let name = displayName(url)
            let item = Item(
                id: "app:" + resolved, title: name, subtitle: "Application", kind: .application,
                action: .open(url))
            candidates.append(Candidate(item, alternatives: [fileName], weight: 2))
        }
        for root in roots { walk(root, depth: depth, found: add) }
        for url in extras where FileManager.default.fileExists(atPath: url.path) { add(url) }
        return candidates
    }

    static func walk(_ folder: URL, depth: Int, found: (URL) -> Void) {
        // Not .skipsHiddenFiles: /Applications/Safari.app is a symlink into a cryptex, flagged hidden.
        let entries =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey]))
            ?? []
        for url in entries where !url.lastPathComponent.hasPrefix(".") {
            if url.pathExtension == "app" {
                found(url)
            } else if depth > 0, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                walk(url, depth: depth - 1, found: found)
            }
        }
    }

    /// The localised name Finder shows, without ".app".
    public static func defaultDisplayName(_ url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// The panes of System Settings, read from the extensions that provide them, so the list follows the
/// macOS version instead of a hard-coded table.
public enum SettingsPanes {
    public static let standardDirectory = URL(filePath: "/System/Library/ExtensionKit/Extensions")

    public static func scan(directory: URL = standardDirectory) -> [Candidate] {
        let entries =
            (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var seen: Set<String> = []
        return entries.compactMap { url in
            guard url.pathExtension == "appex", let bundle = Bundle(url: url), let info = bundle.infoDictionary,
                let identifier = info["CFBundleIdentifier"] as? String,
                let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
                attributes["EXExtensionPointIdentifier"] as? String == "com.apple.Settings.extension.ui",
                let settings = attributes["SettingsExtensionAttributes"] as? [String: Any],
                settings["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true,
                let name = readableName(
                    localized: bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
                    raw: info["CFBundleDisplayName"] as? String),
                seen.insert(name).inserted,
                let target = URL(string: "x-apple.systempreferences:" + identifier)
            else { return nil }
            let item = Item(
                id: "pane:" + identifier, title: name, subtitle: "System Settings", kind: .settings,
                action: .open(target))
            return Candidate(item)
        }
    }

    /// The localised name when there is one. Otherwise the raw name, unless it is an internal one like
    /// "PowerPreferences" or "HeadphoneSettingsExtension" that nobody would recognise.
    static func readableName(localized: String?, raw: String?) -> String? {
        if let localized, !localized.isEmpty { return localized }
        guard let raw, !raw.isEmpty else { return nil }
        let chars = Array(raw)
        let isInternal = zip(chars, chars.dropFirst()).contains { $0.isLowercase && $1.isUppercase }
        return isInternal ? nil : raw
    }
}

/// The Spotlight query for files whose name has a word starting with each word typed.
public enum FileQuery {
    public static func spotlightQuery(for query: String) -> String? {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        let names = words.map { "kMDItemDisplayName == \"\(escape(String($0)))*\"cdw" }
        // Apps come from AppCatalog, which knows their localised names.
        return (names + ["kMDItemContentType != \"com.apple.application-bundle\""]).joined(separator: " && ")
    }

    static func escape(_ word: String) -> String {
        var escaped = ""
        for c in word {
            if c == "\\" || c == "\"" || c == "*" || c == "'" { escaped.append("\\") }
            escaped.append(c)
        }
        return escaped
    }
}

/// Turns what Spotlight found into results: one per path, without clutter, ranked up when recently used.
public enum FileResults {
    public struct Found: Sendable {
        public var path: String
        public var isFolder: Bool
        public var lastUsed: Date?

        public init(path: String, isFolder: Bool, lastUsed: Date?) {
            self.path = path
            self.isFolder = isFolder
            self.lastUsed = lastUsed
        }
    }

    /// Caches, app internals, dot-folders, and build output match plenty of names and are never what
    /// anyone is looking for.
    static let clutter = ["/Library/", "/.", ".app/", "/node_modules/", "/target/", "/DerivedData/", "/__pycache__/"]

    public static func candidates(_ found: [Found], home: String, now: Date) -> [Candidate] {
        // Spotlight can list one file twice, for instance while it re-indexes it.
        var seen: Set<String> = []
        return found.compactMap { file in
            guard !isClutter(file.path), seen.insert(file.path).inserted else { return nil }
            return candidate(file, home: home, now: now)
        }
    }

    static func isClutter(_ path: String) -> Bool {
        clutter.contains { path.contains($0) }
    }

    static func candidate(_ file: Found, home: String, now: Date) -> Candidate {
        let url = URL(filePath: file.path, directoryHint: file.isFolder ? .isDirectory : .notDirectory)
        let parent = url.deletingLastPathComponent().path
        let shown = parent == home || parent.hasPrefix(home + "/") ? "~" + parent.dropFirst(home.count) : parent
        let item = Item(
            id: "file:" + file.path, title: url.lastPathComponent, subtitle: shown,
            kind: file.isFolder ? .folder : .file, action: .open(url))
        // Something opened this week is more likely the one you mean than something from years ago, and
        // either beats a file nobody has ever opened, which is usually generated.
        let weight: Int
        if let lastUsed = file.lastUsed {
            let age = now.timeIntervalSince(lastUsed)
            weight = age < 7 * 86400 ? 8 : age < 30 * 86400 ? 4 : 0
        } else {
            weight = -12
        }
        return Candidate(item, weight: weight)
    }
}
