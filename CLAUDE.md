# Working in this repository

<!-- standard:begin about -->
Common Command is a native macOS launcher, a Spotlight replacement, written in Swift (AppKit plus SwiftUI) with no package dependencies. It is part of the Common Tools family with Common Stats, Common Keys, Common Bar, and Common Glyph.
<!-- standard:end about -->

## The seam

Do all automation through `scripts/task`. CI and the git hooks call nothing else.

```sh
scripts/task fmt          # format in place
scripts/task fmt:check    # swift format lint --strict
scripts/task lint         # fmt:check, then a debug build with warnings as errors
scripts/task test [name]  # the Swift Testing suites; a name filters them
scripts/task build        # universal "build/Common Command.app", signed (see scripts/dev-cert)
scripts/task package      # dist/CommonCommand.zip and checksums, as a release publishes them
scripts/task run          # build, quit the running copy, open the new one
scripts/task check        # lint + test + build: what CI runs
```

## Workflow

- Never commit to `main`. It only moves forward when a pull request is merged; the `pre-push` hook and branch protection both enforce this.
- One unit of work gets one worktree, one branch, and one pull request: `scripts/agent start <type>/<slug>`, then work in the printed path and finish with `scripts/agent ship "<type>(scope): subject" "<why>" --body-file <pr.md>`, where the body states the problem, the approach, and where a reviewer should be sceptical. It commits, checks, opens the pull request with auto-merge, keeps it rebased while CI runs, and cleans up after the merge. If it stops on a failed check or a conflict, fix the cause and run it again.
- Branch types: `feat fix chore docs perf refactor test`. The branch's first commit names the pull request and the squash commit on `main`.
- Never use `--no-verify`.
- User-facing changes go under `## [Unreleased]` in `CHANGELOG.md` in the same pull request. The site shows each release's section as "What's new".
- Release with `scripts/release <version>`. Never tag by hand.
- This repository follows the Common Tools app standard (`standard/` in oddurs/common-tools). Change shared files there and apply them to every app; only the regions between `standard:begin` and `standard:end` belong to this app.

## Commits

Conventional Commits: `type(scope): subject`. Write the subject in the imperative, at most 72 characters, with no trailing period. The body says why. Never add assistant or tool attribution: no co-author trailers, no "generated with" footers. The `commit-msg` hook rejects them.

## Code

<!-- standard:begin code -->
- `Sources/CommandKit` holds matching, ranking, usage, the calculator, link detection, and the catalogs, and contains no UI. `Sources/CommonCommand` holds the app shell: hotkey, panel, menu bar item, Settings, and the Spotlight file query.
- Speed is the product. Ranking runs on the main thread on every keystroke and must stay well under a millisecond for a real catalog; `PerformanceTests` enforces budgets. Don't loosen a budget to make a change pass. Anything slower (Spotlight, directory scans) runs off the main thread and never blocks the list.
- Public APIs only, and no permissions: the hotkey is Carbon's `RegisterEventHotKey`, files come from `MDQuery`, panes from the System Settings extension bundles. Don't add anything that needs Accessibility, Input Monitoring, or Full Disk Access.
- The panel is a non-activating `NSPanel`. Don't call `NSApp.activate()` when showing it; the user's app must stay frontmost.
- A bug fix comes with the test that would have caught it. Ranking changes need a test showing the order they fix.
- `CommonTools.swift` is shared word for word across the Common Tools apps. Change it in all of them together.
- For visual review, use `swift build && .build/debug/CommonCommand --snapshot out.png "query" [--theme light|dark]` and inspect `out.png`. It renders offscreen; never drive the live screen with synthesized keys or the global shortcut to check a design.
<!-- standard:end code -->
