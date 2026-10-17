# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- A launcher panel opened with a global shortcut (⌥Space by default, recordable in Settings). It doesn't activate the app, so the app you were in stays frontmost.
- Search across apps, System Settings panes, Common Command's own commands, files and folders from the Spotlight index, and the web.
- Fuzzy matching on word starts and runs of letters, with case and accent folding and bold matched letters.
- Learning: the result chosen for a query comes first next time, and frequently opened items rise, decaying with a one-week half-life.
- A calculator with percent, powers, factorial, functions, constants, and region-aware decimal separators. Return copies the result.
- Link detection for web addresses, `localhost`, and IPv4 addresses.
- Keyboard control: arrows, ⌃P/⌃N, Tab, Return, ⌘Return to show in Finder, and ⌘1–⌘9 with hints while ⌘ is held.
- Settings: shortcut, theme, size, translucency, visible results, sources, search engine, menu bar item, and open at login.
- Liquid Glass on macOS 26 and the popover material on earlier versions, or a solid background.
- System Settings topics and keywords from System Settings' own search terms, so "dark mode", "low power", or "firewall" find the right pane, shown with the pane's icon.
- A result chosen for a query also leans shorter and longer starts of that query its way, so you can type less next time.
- Unit conversions such as "10 km to mi", "70 f in c", or "5 GB in MB", offline, with Return to copy.
- Moving the pointer over a result selects it, and apps, files, and folders can be dragged out of the panel.
- A macOS 26 look: a glass capsule for the field and a glass card for results, grouped into Top Hit, Applications, System Settings, Files, and Search the Web. A short fade on opening, none with Reduce Motion.
- "No Results" when nothing matches and web search is off.
- Scopes, as in Spotlight on macOS 26: ⌘1 Apps, ⌘2 Files, ⌘3 Actions, also as buttons in the field. With nothing typed, a scope lists every app and pane, recent files, or all actions.
- Actions: run shortcuts from the Shortcuts app, and quit or hide running apps.
- A live preview of the panel at the top of Settings.
- A warning in Settings and the menu bar menu when the shortcut is also Spotlight's or Alfred's, saying where to change theirs. macOS accepts both without an error, so the clash was silent.
- VoiceOver reads the selected result as it changes.

### Changed

- ⌘1–⌘9 choose a scope instead of opening the nth result, to match Spotlight.

- Rows say less: no "Application" label, a pane's name instead of "System Settings ›", and file paths keep their start and end when shortened.
- System Settings topics match only where each typed word starts a word of the topic, and keywords only from the fourth letter, so a short query finds apps instead of a dozen loosely related settings.

### Fixed

- A file Spotlight listed twice showed as two rows.

[Unreleased]: https://github.com/oddurs/common-command/commits/main
