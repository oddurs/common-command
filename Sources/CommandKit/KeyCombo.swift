/// A global keyboard shortcut: a virtual key code and its modifiers.
public struct KeyCombo: Codable, Equatable, Sendable {
    public struct Modifiers: OptionSet, Codable, Sendable, Hashable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        // The same bits as NSEvent.ModifierFlags, so an event's flags convert with a mask.
        public static let shift = Modifiers(rawValue: 1 << 17)
        public static let control = Modifiers(rawValue: 1 << 18)
        public static let option = Modifiers(rawValue: 1 << 19)
        public static let command = Modifiers(rawValue: 1 << 20)
        public static let all: Modifiers = [.shift, .control, .option, .command]
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.all)
    }

    static let space: UInt16 = 49
    /// ⌥Space: free on a stock Mac, unlike ⌘Space, which Spotlight holds.
    public static let standard = KeyCombo(keyCode: space, modifiers: .option)

    /// The modifier bits Carbon's RegisterEventHotKey takes.
    public var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= 0x0100 }
        if modifiers.contains(.shift) { flags |= 0x0200 }
        if modifiers.contains(.option) { flags |= 0x0800 }
        if modifiers.contains(.control) { flags |= 0x1000 }
        return flags
    }

    /// A shortcut must hold ⌘, ⌥, or ⌃, or it would swallow ordinary typing. Function keys are the exception.
    public var isUsable: Bool {
        !modifiers.isDisjoint(with: [.command, .option, .control]) || Self.functionKeys[keyCode] != nil
    }

    /// "⌥Space", "⌃⇧K". `keyName` reads a character key on the current keyboard layout.
    public func display(keyName: (UInt16) -> String?) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (Self.specialKeys[keyCode] ?? keyName(keyCode)?.uppercased() ?? "Key \(keyCode)")
    }

    static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    /// Keys whose name doesn't depend on the keyboard layout.
    static let specialKeys: [UInt16: String] = functionKeys.merging([
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 76: "⌤",
    ]) { a, _ in a }
}
