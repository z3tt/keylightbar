# AGENTS.md — working agreement for this repo

## Git workflow
- The owner also edits this repo on github.com: run `git pull --rebase origin main`
  before every push.
- Work with branches + PRs: for anything beyond a small fix (features,
  behavior changes, multi-commit work), create a `feature/…` or `fix/…`
  branch, push it, and open a PR for the owner to review. Merge only after
  approval.
- Working directly on `main` is fine for small fixes and docs tweaks —
  commit locally whenever a change compiles (`swiftc main.swift` → 0
  errors); small working steps are fine, one logical change per commit.
- During interactive or drafting work (e.g. iterating on website copy),
  commit each step locally but do NOT push every time — push only when
  the owner asks or when the session's work is settled.
- If it's unclear whether a change is small enough for `main`, ask the
  owner once before committing.
- Still ask first: version tags, GitHub releases, and anything destructive
  (force-push, branch deletion).

## Multiple concurrent agent sessions
- Branches isolate commits, not the working tree: all sessions on one clone
  share the same checkout, and uncommitted edits collide across branch
  switches.
- For parallel sessions, give each its own checkout:
  `git worktree add ../keylightbar-<topic> <branch>` (or a separate clone).
  Sessions can then build, test, and switch branches independently.
- Before another session switches branches in a shared clone: commit (or
  stash) WIP first — never carry uncommitted edits across a switch.
- One app instance at a time: quit other KeylightBar builds before testing
  a fresh one, or the icon you're watching may not be the binary under test.

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

## Session notes
- Every session appends a dated entry to `docs/NOTES.md` when closing a
  unit of work: what shipped, decisions and why, gotchas, next steps.
- Substantial new work starts with a brief (`docs/brief.md`) the owner
  reviews before building. Its step list is a living plan — keep it
  current and let it grow into the to-do list. Exploratory design work
  (like the dot arc) uses a goal statement + iteration loops instead of
  a fixed definition of done.
- Ambiguous or high-stakes requests: interview the owner first — a
  batched set of 2–4 high-leverage questions — then draft the brief.
  Clear requests: draft and mark assumptions. Never stall on
  interchangeable details — pick and surface.
- Discrete future work belongs in GitHub issues; long-running narrative
  state lives in `docs/NOTES.md` — not in chat.
