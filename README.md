# Common Command

[![CI](https://github.com/oddurs/common-command/actions/workflows/ci.yml/badge.svg)](https://github.com/oddurs/common-command/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A small, fast launcher for macOS. Press ⌥Space, type a few letters, press Return. Apps, System Settings panes, files, sums, and web searches, in one quiet panel a little smaller than Spotlight's.

Common Command is built to feel like part of macOS:

- **It matches your Mac.** The panel follows light and dark mode, uses Liquid Glass on macOS 26 (the popover material before that), and highlights with your accent colour. Choose a fixed theme, a solid background, or a size in Settings.
- **It stays out of the way.** The panel never activates the app, so the app you were in stays frontmost and keeps its menu bar. Escape, or a click anywhere else, returns you to it with nothing to restore.
- **It learns.** Whatever you choose for a query comes first the next time you type it, and leans the same way for a shorter start: choose Safari for "safari" once, and "sa" prefers it too. Things you open often rise for every query. Usage decays with a one-week half-life, so last year's habits fade.
- **Typing is forgiving.** "vsc" finds Visual Studio Code, "sys set" finds System Settings, "cafe" finds Café. Matched letters are drawn in bold.

Free and open source under the MIT licence. No network access except the web searches and links you open, no analytics, no helper tools, and no Accessibility or Full Disk Access permissions.

## Install

Requires macOS 14 or later.

1. Download [CommonCommand.zip](https://github.com/oddurs/common-command/releases/latest/download/CommonCommand.zip) from the [latest release](https://github.com/oddurs/common-command/releases/latest), unzip it, and move **Common Command** to Applications.
2. Open it. The build is signed but not notarized, so the first time macOS will say it can't verify the developer. Go to **System Settings › Privacy & Security** and click **Open Anyway**. Alternatively, run:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Common Command.app"
   ```

3. Turn on **Open at login** in Settings.

### Using ⌘Space

Spotlight owns ⌘Space. To give it to Common Command, turn off **Show Spotlight search** in **System Settings › Keyboard › Keyboard Shortcuts › Spotlight**, then record ⌘Space in Common Command's Settings. Settings has a button that opens the right page.

## Usage

| Key | Does |
| --- | --- |
| ⌥Space | Open or close the panel (change it in Settings) |
| ↑ ↓, ⌃P ⌃N, Tab | Move the selection |
| ↩ | Open the selected result, or copy a calculation |
| ⌘↩ | Show the selected file or app in Finder |
| ⌘1 … ⌘9 | Open a result directly; hold ⌘ to see the numbers |
| ⎋ | Close |

What a query finds, in order:

1. **Links.** `github.com/apple`, `https://…`, and `localhost:3000` open in your browser. Only well-known endings count, so `notes.md` and `Info.plist` stay file searches.
2. **Calculations.** `2^10`, `15% * 80`, `sqrt(2)`, `(1+2)(3+4)`, `5!`, with `pi`, `e`, and functions such as `sin`, `log`, and `round`. Return copies the result. Numbers follow your region, so `1,5 + 1` works where the comma is the decimal separator. A bare number isn't treated as a sum, so `1Password` and `2024` stay searches.
3. **Apps, System Settings, and Common Command's own commands** (Settings, Quit). Settings covers each pane and the topics inside it, found by the same keywords System Settings' own search uses: "dark mode" finds Appearance, "low power" finds Low Power Mode, "firewall" finds the firewall switch. Panes show their own icons. Laptop-only settings appear only on laptops.
4. **Files and folders** in your home folder whose name has a word starting with each word you typed. Build output, caches, and dot-folders are left out, and files you've opened recently rank higher.
5. **A web search** with your chosen engine: Google, DuckDuckGo, Bing, Kagi, Ecosia, or Startpage.

Each of these except apps can be turned off in Settings. The last query comes back selected when you reopen the panel, so typing replaces it and Return repeats it.

## Settings

- **Shortcut**: click and press a new one. Escape cancels; Delete restores ⌥Space.
- **Appearance**: theme (System, Light, Dark), size (Small, Medium, Large), translucency, and how many results show before the list scrolls.
- **Search**: System Settings, files, calculator, and web search on or off, and the search engine.
- **General**: show in the menu bar, and open at login. With the menu bar item hidden, open Common Command from Finder to get back to Settings.

## Performance

Measured on an M4 Pro with a release build:

- Ranking every app, pane, and command takes about 0.1 ms per keystroke. The test suite ranks 2,000 names in about 0.6 ms.
- From the shortcut to the panel's first drawn frame takes about 9 ms. The panel is built once and reused.
- File results come from Spotlight's index through `MDQuery`, capped at 60 matches, so a one-letter query doesn't make Spotlight gather thousands. The query starts 35 ms after you stop typing and never holds up the list above it.
- The app folders are rescanned in the background, at most every 30 seconds and only while you use the panel, in about 11 ms. System Settings panes are read once per launch.
- Nothing runs while the panel is closed.

`PerformanceTests` fails if ranking or scanning gets about 10× slower.

## Build from source

The Command Line Tools are enough; Xcode is not required.

```sh
scripts/task build                 # universal build → build/Common Command.app
mv "build/Common Command.app" /Applications/
```

## Development

```sh
scripts/setup           # once: wire the git hooks
scripts/agent doctor    # check tools and repository state
```

| Command | Does |
| --- | --- |
| `scripts/task check` | lint + test + build, exactly what CI runs |
| `scripts/agent start <type>/<slug>` | new worktree and branch from `origin/main` |
| `scripts/agent commit "<type>: subject"` | Conventional Commit, checked by the hook |
| `scripts/agent pr` | full check, push, open the pull request |
| `scripts/agent sync` | rebase onto `origin/main` |
| `scripts/agent done` | after merge: remove the worktree and branch |
| `scripts/agent list` | worktrees, branches, and pull request state |

See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow.

`swift build && .build/debug/CommonCommand --snapshot out.png "query" --theme dark` opens the real panel with the query typed, captures it, and quits. Use it to review design changes. It uses its own settings, so it never changes yours.

Layout:

- `Sources/CommandKit`: matching, ranking, usage history, the calculator, link detection, the app and System Settings catalogs, shortcut and layout models. No UI, so it can be tested on its own.
- `Sources/CommonCommand`: the global shortcut, the panel, the menu bar item, Settings, and the Spotlight file query.
- `Tests/CommandKitTests`: unit and performance tests.

## Licence

MIT. See [LICENSE](LICENSE).
