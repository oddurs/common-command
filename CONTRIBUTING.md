# Contributing

Thanks for helping. Common Command stays small on purpose, so open an issue before starting anything large.

## Setup

```sh
scripts/setup          # wire the git hooks, once
scripts/agent doctor   # check tools and repository state
```

You need macOS 14 or later and Swift 6 or later. The Command Line Tools are enough.

## Workflow

Every change goes through a pull request. `main` only moves forward when a pull request is merged; branch protection and the `pre-push` hook both enforce this.

Each change gets its own worktree, branch, and pull request:

```sh
scripts/agent start fix/calc-percent-precedence  # creates ../.worktrees/common-command/fix/calc-percent-precedence
cd ../.worktrees/common-command/fix/calc-percent-precedence
# ... make the change ...
scripts/agent commit "fix(calc): apply percent before multiplication"
scripts/agent pr                         # runs the full check, pushes, opens the PR
scripts/agent done                       # after merge: removes the worktree and branch
```

Branch names are `<type>/<slug>`, where type is one of `feat fix chore docs perf refactor test`.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): subject`. Write the subject in the imperative, keep it to 72 characters, and leave off the trailing period. The body explains why; the diff already shows what. The `commit-msg` hook checks this.

Don't add tool or assistant attribution lines (co-author trailers, "generated with" footers). The hook rejects them.

## Checks

```sh
scripts/task check   # lint + test + build, the same thing CI runs
```

A branch must pass this before it becomes a pull request. A bug fix comes with the test that would have caught it. Behaviour that depends on AppKit or Spotlight belongs in the app target; matching, ranking, and parsing belong in CommandKit, where the tests can reach them.

## Review

This is a solo-maintained project, so branch protection requires zero approvals and the maintainer merges their own pull requests once CI is green. The `required` status check and up-to-date branches are still enforced.
