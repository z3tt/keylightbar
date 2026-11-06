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

## 2026-11-06 · slider gradient guides, first draft (feature/slider-gradient-guides)
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
- **Next**: review the three screenshots in `~/gdrive/ai-artifacts/keylightbar/`
  (light, dark, light w/ Bright preset), iterate, then README + GIF refresh
  + PR.

## 2026-11-04 · v1.2.2 — perceptual swatch dots (full design arc)
- **Dot formula (final)**: hue+chroma from temperature anchors (blue 143 /
  gray 243.5 ≈ 4950 K / amber 344, RGB-interpolated), saturation ×1.8,
  brightness → OKLCH perceptual lightness L = 0.35 + 0.50·b/100,
  chroma gamut-clamped. Hexes: Work #8b754f, Meet #6b92c0, Night #7d5200,
  Chill #603c02, Bright #cdcece, Cold #5283bc, Warm #ae7117.
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
