import Carbon.HIToolbox
import CommandKit

enum HotKeyError: LocalizedError {
    case unavailable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unavailable(let status) where status == eventHotKeyExistsErr:
            "Another app already uses this shortcut."
        case .unavailable(let status):
            "macOS didn't accept this shortcut (error \(status))."
        }
    }
}

/// One system-wide shortcut, through Carbon's RegisterEventHotKey: the only public API that takes a key
/// before the frontmost app sees it without asking for Accessibility or Input Monitoring access.
@MainActor
final class HotKey {
    var onPress: (() -> Void)?
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Delivered on the main thread, at key-down, which is what keeps opening the panel immediate.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.onPress?() }
                return noErr
            }, 1, &spec, context, &handler)
    }

    func register(_ combo: KeyCombo) throws {
        unregister()
        let id = EventHotKeyID(signature: 0x4343_6D64, id: 1)  // "CCmd"
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode), combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &registration)
        guard status == noErr else {
            registration = nil
            throw HotKeyError.unavailable(status)
        }
    }

    func unregister() {
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
    }
}

/// The name a key code types on the current keyboard layout: "Z" on a QWERTZ keyboard's Y key.
func keyName(_ keyCode: UInt16) -> String? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
        let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    return data.withUnsafeBytes { bytes -> String? in
        guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: chars, count: length)
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
    }
}

extension KeyCombo {
    var displayName: String { display(keyName: keyName) }
}

/// The global shortcuts Spotlight and Alfred hold on this Mac, read from their preferences. Missing or
/// unreadable files just mean nothing to warn about.
func otherAppsShortcuts() -> [Conflicts.Holder] {
    var holders: [Conflicts.Holder] = []
    if let symbolic = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") {
        holders += Conflicts.spotlight(symbolic)
    }
    let alfred = URL.applicationSupportDirectory.appending(path: "Alfred/prefs.json")
    if let data = try? Data(contentsOf: alfred), let file = Conflicts.alfredHotkeyFile(prefsJSON: data),
        let prefs = NSDictionary(contentsOf: file) as? [String: Any], let holder = Conflicts.alfred(prefs)
    {
        holders.append(holder)
    }
    return holders
}
