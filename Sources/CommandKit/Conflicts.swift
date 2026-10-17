import Foundation

/// Other apps' global shortcuts, read from where they keep them. macOS lets two apps register the same
/// shortcut without an error, so the only way to warn about a clash is to look.
public enum Conflicts {
    public struct Holder: Equatable, Sendable {
        public var owner: String
        public var combo: KeyCombo
        /// Where to change it, in words.
        public var whereToChange: String
    }

    /// Spotlight's two shortcuts from `com.apple.symbolichotkeys`: 64 shows Spotlight, 65 its Finder window.
    public static func spotlight(_ symbolicHotKeys: [String: Any]) -> [Holder] {
        let names = ["64": "Spotlight", "65": "Spotlight's Finder search"]
        return names.keys.sorted().compactMap { id in
            guard let entry = symbolicHotKeys[id] as? [String: Any], (entry["enabled"] as? NSNumber)?.boolValue == true,
                let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [NSNumber], parameters.count == 3
            else { return nil }
            return Holder(
                owner: names[id]!,
                combo: KeyCombo(
                    keyCode: parameters[1].uint16Value,
                    modifiers: KeyCombo.Modifiers(rawValue: parameters[2].uintValue)),
                whereToChange: "System Settings › Keyboard › Keyboard Shortcuts › Spotlight")
        }
    }

    /// Where Alfred keeps this Mac's hotkey, from its `prefs.json`: the preferences folder (which may be
    /// synced elsewhere) and this Mac's subfolder.
    public static func alfredHotkeyFile(prefsJSON: Data) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: prefsJSON) as? [String: Any],
            let folder = json["current"] as? String, let hash = json["localhash"] as? String
        else { return nil }
        return URL(filePath: folder).appending(path: "preferences/local/\(hash)/hotkey/prefs.plist")
    }

    public static func alfred(_ hotkeyPrefs: [String: Any]) -> Holder? {
        guard let main = hotkeyPrefs["default"] as? [String: Any], let key = main["key"] as? NSNumber,
            let modifiers = main["mod"] as? NSNumber
        else { return nil }
        return Holder(
            owner: "Alfred",
            combo: KeyCombo(keyCode: key.uint16Value, modifiers: KeyCombo.Modifiers(rawValue: modifiers.uintValue)),
            whereToChange: "Alfred Preferences › General › Alfred Hotkey")
    }

    /// The first app that also holds `combo`.
    public static func holder(of combo: KeyCombo, among holders: [Holder]) -> Holder? {
        holders.first { $0.combo == combo }
    }
}
