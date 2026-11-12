# KeylightBar — project notes & decision log

Durable record for cross-session work. Each session appends a dated
entry (see AGENTS.md). Releases: https://github.com/z3tt/keylightbar/releases

## Architecture (stable)
- Single-file Swift app (`main.swift`), zero dependencies, `make bundle` builds
  (reads `appVersion` from source, regenerates Info.plist, ad-hoc codesigns).
- Website in `docs/` (plain HTML + scss → css, compiled by CI on push; Pages
  serves it at https://keylightbar.cedricscherer.com/).
- Presets persist in UserDefaults (`keylight.presets`); defaults apply only
  when nothing is stored — editing never reorders, Reset Defaults restores
  order + values.
- Every freshly compiled binary needs its own macOS Local Network grant —
  silent failures are that, not a bug. `defaults read com.cedricscherer.keylightbar keylight.host` prints the light's address.

## 2026-11-12 · stray-HID wake analysis → fix/stray-hid-wakes (PR #16)
- **Symptoms**: light on when coming into the office (lid closed, screens
  asleep, nobody touching anything, Nov 12 morning) + 2–3 days of "didn't
  turn on after wake". **Diagnosis from pmset/log evidence**: the wake
  gate was circular for HID-caused wakes — the Bluetooth/USB packet that
  wakes the Mac also resets the CGEventSource idle clock, so it always
  read as "fresh input" (light on with nobody there: only full wake was
  08:43:06, cause `centauri-beta/HID Activity` via `wifibt`, minutes
  before the owner walked in). Symmetrically, an unattended wake fired
  screensDidWake *before* arrival, so the real keypress later fired no
  event at all → "didn't wake up".
- **Fix (PR #16)**: with the lid closed, presence = *continued* input
  (idle-clock sampling; the clock gains exactly one sample interval
  between readings when nobody types, so a short reading = an event).
  Unconfirmed wakes are parked (`pendingUnattendedWake`) and the sampler
  turns the light on when real input follows — no new screensDidWake
  needed. Time-of-day switching requires the same confirmed presence.
  Wake retries 5×3 s → 20×3 s (~60 s; Wi-Fi can re-associate slowly).
  Gotcha from the archival dig: the retry window was ~20 s since fcb46fe
  (Oct 28) — never longer; the longer-window memory was false.
- **Diagnostics for next time** (the light's own state was never logged
  anywhere — retroactive attribution impossible):
  `log show --last 1h --predicate 'subsystem == "com.cedricscherer.keylightbar"'`
  + the Nov 3 recipe: `pmset -g log | grep -E "Wake from|DarkWake"`.
- **Not included, deferred (issue: Turn Off race)**: willSleep → `turnOff()`
  is a single unverified PUT during sleep teardown — if it dies, the
  light simply stays on overnight; alternative (unverifiable) explanation
  for the Nov 12 morning. Needs owner decision: retry the off-PUT, and
  whether an on-light during a confirmed-unattended wake may be turned
  off (would also undo a manual flip).
- **Verification**: `make bundle` → 0 errors (expected NetService
  deprecations only). Behavior NOT hand-tested yet — needs a real
  overnight cycle; scenarios listed in PR #16. Two Nov 6 KeylightBar
  crash reports checked and ruled out: dev builds (parent zsh/VSCode
  from the UI-session snapshot work), not the production app.

## 2026-11-06 · v1.3.0 SHIPPED (LIVE)
- https://github.com/z3tt/keylightbar/releases/tag/v1.3.0 — Latest,
  KeylightBar.zip attached, notes from
  `~/gdrive/ai-artifacts/keylightbar/release-notes-v1.3.0.md`. Tagged
  on merged main; /Applications refreshed from the same build.
  Bundles: gradient-strip editor (#13), perceptual OKLCH dots (#14),
  neutral Bright default, web recompute. The v1.2.2 release page carries
  the dated correction. GIF refresh still parked until the features are
  advertised.
- Feature release bundling the two merged arcs: the preset editor's
  gradient strips (#13) and the perceptual OKLCH dots (#14, including
  Bright's default → 100/243 neutral and the web hex recompute). Editor
  layout (temp-first sliders, strips, 464pt window) rides along.
- Release path per repo convention: version bump branch → PR → merge →
  `gh release create v1.3.0 "KeylightBar.zip#KeylightBar.zip" --notes-file
  … --latest`. Zip = `zip -r KeylightBar.zip KeylightBar.app` from the
  post-merge build.
- The published v1.2.2 release notes promised the OKLCH dots that the
  v1.2.2 binary never contained (tag verified: HSV formula, Bright 220).
  Prefaced its GitHub release body with a dated correction pointing to
  v1.3.0; original text kept below the notice.

## 2026-11-06 · perceptual dots resurrected (feature/perceptual-dots)
- The two orphan OKLCH commits from feature/perceptual-swatches
  (3d00daf lightness rework, fe6e488 Bright → 100/243 neutral) cherry-
  picked onto post-#13 main; conflicts resolved toward OKLCH — the 0.94
  HSV band from PR #13 was the stopgap this replaces. Dots, strips, web
  hexes all re-derive; the fourteen scss values match the formula output
  compiled straight from main.swift (#8b754f … #cdcece family).
- Gotcha for any future port of the formula: the HSB carrier lightness is
  `0.40 + 0.48·b/100` (tops at 0.88) — misreading that as a band capped
  at 0.48 halves the chroma (bit the Python generator first).
- Contrast under OKLCH (light menus): Work 4.09:1, Meet 2.99, everything
  colored ≥ ~3; Bright 1.46:1 by design (temp 243 = zero chroma → pure
  gray-white #cdcece — semantically honest for a neutral preset).
- Owner live verdict (PR #14): better overall; Bright reads darker but
  far more present — "barely visible in merged on light". Pure gray-white
  Bright accepted, no chroma nudge needed.
- Fresh Windows… still need Local Network grants per binary (standing).

## 2026-11-06 · slider gradient guides, first draft (feature/slider-gradient-guides)
- **Iteration 1 (owner review)**: more spacing between settings (window
  430→448, sections re-spaced); the "143 coldest · 344 warmest" hint
  removed — the strips are CVD-safe (blue↔amber on a strong lightness
  contrast, achromatic midpoint, brightness ramp pure lightness) and carry
  the scale themselves; strip inset fixed to span the slider's full track
  (measured from screenshots: knob-center travel = frame 125–330, so the
  draft's 9pt pad broke knob-color alignment at the extremes).
- **Iteration 2 (owner review)**: "Bright reads dim" — swatch value band
  widened 0.40–0.88 → 0.40–0.94 (floor kept, dim presets stay deep;
  dots and strips both derive from presetSwatchColor, so both moved).
  Contrast analysis:
  `~/gdrive/ai-artifacts/keylightbar/dots-contrast-preview.html` +
  `generators/dot-contrast.py` (static HTML — Quick Look can't run JS,
  see learnings). Verdict: every dot ≥ ~3:1 on light menus except Bright
  (near-neutral temp 220 → pale in any band, 1.42:1) and Work at 2.99:1 —
  owner judged clearly visible.
- **Iteration 3 (owner review)**: sliders reordered — temperature first,
  brightness second (temperature sets the character of the light,
  brightness its intensity; owner spotted the brightness strip following
  temperature and loved the crossing-slices behavior). Pixel-verified:
  upper strip = temp axis, lower = brightness ramp.
- **Iteration 4 (owner review, live)**: more space below the strips
  (strip→buttons 16→24pt, temp-strip→brightness block 11→19pt, window
  448→464) — owner tested the running PR build live and verified:
  "love it". Editor layout is settled with this round.
- **Web coupling** (docs gotcha exercised): the site's menu dots and
  `--preset-accent` stripes are hardcoded formula output — all fourteen
  hexes were one step stale after the band widening and were recomputed
  (docs/scss only, css is CI-compiled). Old -> new, e.g. Work
  #9d8760 -> #a48c64, Bright #afc6e0 -> #bbd3f0; docs/README formula
  constant updated to 0.54. Art-directed glows/backgrounds untouched.
- **What**: each manager slider now carries a thin gradient strip sampled
  from `presetSwatchColor` — crossing slices through the dot color map:
  temp strip = temp swept 143–344 at the **current brightness**, bright
  strip = brightness swept 0–100 at the **current temperature**. The color
  under each knob is the selected preset's dot, live. Editor layout
  re-stacked (rows +6pt, strips at y=97 and y=63; window height stays 430).
- **Decisions**: crossing slices over a fixed-lightness temp strip (the
  stronger dot-link; pale-slice risk deferred to review — see the
  Bright-preset screenshot); strips inset 9pt to align with the NSSlider
  track, not the knob-caps; strips reuse the same function, so they can
  never drift from the dots; gray on null selection (no slice defined).
- **In-process screenshots** (new debug hooks, env-gated, default no-op):
  `KEYLIGHTBAR_DEBUG_UI=1` auto-opens the manager;
  `KEYLIGHTBAR_SNAPSHOT=path` + `KEYLIGHTBAR_DEBUG_ROW=n` render the window
  content to a PNG via `cacheDisplay`. No `screencapture`, so no Screen
  Recording permission needed (the agent host lacks it). Gotchas learned:
  NSGraphicsContext(bitmapImageRep:) traps when the rep has no alpha →
  samplesPerPixel 4 + hasAlpha true only; cacheDisplay skips the window's
  themed background → compose `windowBackgroundColor` behind it (CoreGraphics
  draw without flip; the AppKit NSImage composite path misplaces content at
  2x); direct rep→PNG worked at 1x but the compose path needs the explicit
  CGContext. Generator script: `~/gdrive/ai-artifacts/keylightbar/generators/`.
- **Verification**: `make bundle` 0 errors; strip pixels sampled from the
  PNGs (blue 143 → gray 243.5 → amber 344 on the temp strip; dark→light on
  the bright strip; themed bg light/dark correct). Interactions (slider
  drag, rename, add/remove) not yet hand-tested — that's for when the
  design is approved.
- **Next**: PR from `feature/slider-gradient-guides` (three owner review
  rounds: spacing/track alignment, band widening, slider reorder — all
  approved). GIF refresh deliberately deferred: the strips aren't
  advertised yet, so the old GIF's editor segment is tolerable until the
  feature is announced. OKLCH follow-up: no issue — the owner takes the
  feature/perceptual-swatches commits up directly after this PR merges
  (rebase over presetSwatchColor + web hex recompute apply again).

## 2026-11-04 · v1.2.2 — perceptual swatch dots (full design arc)
- **Dot formula (actually shipped — corrected 2026-11-06)**: hue+sat from
  temperature anchors (blue 143 / gray 243.5 ≈ 4950 K / amber 344,
  RGB-interpolated), saturation ×1.8, brightness → HSV value
  0.40 + 0.48·b/100 (0.40–0.88 band). Shipped hexes: Work #9d8760,
  Meet #5c83af, Night #85590d, Chill #704700, Bright #afc6e0,
  Cold #3c6ba3, Warm #a36700.
- **Correction 2026-11-06**: this entry originally recorded the OKLCH
  rewrite (L = 0.35 + 0.50·b/100, chroma-clamped, Bright → 100/243) as the
  "final" formula — it never shipped. PR #11's base was
  feature/theme-harmonize, not main, so its two commits
  (Encode swatch brightness as perceptual OKLCH lightness; Make Bright the
  neutral full-brightness preset) live only on feature/perceptual-swatches.
  The v1.2.2 tag, main, and the web hexes are all the HSV formula above.
  The owner picks the OKLCH thread up directly after the slider-gradient
  work merges.
- **Design decisions** (PRs #7–#11): dot = identifier/guide, not a legend
  (hue direction true, degree exaggerated; the label does exact ID);
  brightness must read perceptually (HSB value renders saturated hues
  5–10% dimmer — OKLCH fixes it); no outlines (lightness band stays inside
  0.35–0.85 OKLCH: dim = deep colored, never black); web dots are hardcoded
  hexes = app formula output, recompute when defaults change (docs README
  gotcha); web themes hand-art-directed per state, only the card stripes
  (`--preset-accent`) stay coupled to the dots.
- **Default presets changed**: Work 45/220→45/260 (≈4500 K, neutral-warm),
  Bright 100/220→100/243 (≈5000 K, genuinely neutral); order now
  Work, Meet, Night, Chill, Bright, Cold, Warm.
- Each re-sign is a new binary to macOS → stale Local Network entries in
  System Settings are dead records; they prune after the copies are gone
  + a reboot.

## 2026-11-04 · v1.2.1 — bivariate dots + nudge fix
- Hue = temperature with achromatic neutral at the scale midpoint
  (issue #4's original tan@220 misrendered neutral presets);
  lightness = brightness; unattended-wake fix (below) also shipped here.

## 2026-11-03/04 · dark-wake fix (verified via pmset logs)
- macOS dark wakes (Power Nap / Wake-for-network, ~40/night with lid closed)
  fired the screens-wake event and turned the light on overnight. Presence
  gate added: wake requires an open lid or keyboard/mouse input within
  60 s (clamshell desktop use keeps working); the 60 s time-switch timer got
  the same gate. IOKit `AppleClamshellState` + CGEventSource idle time.
- Debugging recipe: `pmset -g log | grep -E "Wake from|DarkWake"` shows
  dark wakes vs attended wakes.

## 2026-11-03 · v1.2 — swatch dots (issue #4), clipping fix, darkening
- Dots drawn via NSImage drawing handler (explicit 2× NSBitmapImageRep
  gets clipped by the menu's 16 pt slot — AppKit loses its point size).
- Web: dots sit before the names (matches NSMenuItem.image), mock menu
  width fit-content, moon emoji dropped from Turn Off.

## Workflow rules that emerged
- Branches + PRs for features/behavior; small fixes/docs → main; ask once
  when unsure (AGENTS.md, both repo-level and global).
- gh CLI (authed) is the release path: `gh release create TAG
  "zip#KeylightBar.zip" --notes-file f --latest`.
- Session-shared artifacts (mockups, comparisons) → `~/gdrive/ai-artifacts/keylightbar/`.
- The system prompt is pinned at session start: mid-session policy or file
  changes only reach *new* sessions.
