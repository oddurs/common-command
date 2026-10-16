import AppKit

/// Never shown, since the app has no Dock icon, but its key equivalents are how ⌘C, ⌘V, ⌘A, and ⌘Z reach
/// the search field and the Settings window, and how ⌘W closes Settings.
@MainActor func makeMainMenu() -> NSMenu {
    let main = NSMenu()
    let app = NSMenu()
    app.addItem(withTitle: "Quit Common Command", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    main.addItem(withTitle: "Common Command", action: nil, keyEquivalent: "").submenu = app

    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

    let window = NSMenu(title: "Window")
    window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
    return main
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController(snapshot: Snapshot.request(from: CommandLine.arguments))
    app.delegate = controller
    app.mainMenu = makeMainMenu()
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(controller) { app.run() }
}
