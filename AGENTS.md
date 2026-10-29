# AGENTS.md — working agreement for this repo

## Git workflow
- The owner also edits this repo on github.com: run `git pull --rebase origin main`
  before every push.
- Commit locally whenever a change compiles (`swiftc main.swift` → 0 errors).
  Small working steps are fine; one logical change per commit.
- Push in logical packages: once a coherent unit of work is complete and runs,
  push the batch — not after every micro-commit. No per-push permission needed;
  that standing rule replaces asking.
- Still ask first: version tags, GitHub releases, and anything destructive
  (force-push, branch deletion).

## Project conventions
- Single-file Swift app (`main.swift`), dependency-free by design — keep it that
  way unless the owner asks otherwise.
- Build with `make bundle` (it also regenerates Info.plist, reading the version
  from `appVersion` in the source).
- Emoji icons 💡/🌑/🔍 and title-cased preset names are intentional; don't "fix" them.
- NetService deprecation warnings are expected and accepted (kept for single-file
  simplicity; NWBrowser is the known modern alternative).
- Every freshly compiled binary needs its own macOS "Local Network" permission
  grant — silent network failures are usually that, not a bug.
