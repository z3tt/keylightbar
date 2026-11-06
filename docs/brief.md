# Brief — Slider gradient guides in the preset manager

## Goal
Make the "Manage Presets…" sliders into a visual guide for the swatch-dot
color model: each slider gets a thin gradient strip sampled from
`presetSwatchColor`, so the color under the knob matches the selected
preset's menu dot. The editor becomes the legend for the menu dots.

## Audience
KeylightBar users tweaking presets — the 143/344 temperature numbers are
developer-speak; the strips make the cool-to-warm scale legible at a glance.

## Approach (first draft: crossing slices)
The dot is one point in a 2D color map (temperature → hue/sat,
brightness → lightness 0.40–0.88). Each strip is the slice through that
map at the current position:

- Temperature strip — temp swept 143→344 at the **current brightness**
- Brightness strip — brightness swept 0→100 at the **current temperature**
- Both update live (selection change, either slider drag), so the color
  under each knob is the dot's color — that is the "link to dots".

Known trade-off accepted for the draft: at brightness 100, the temp strip
runs at 0.88 lightness (pale, may wash out on light windows). Review in
screenshots; fallback is a fixed mid-lightness temp strip.

## Iteration 1 (owner review)
- More breathing room between settings: window height 430 → 448, sections
  re-spaced (table 181 / name 143 / bright slider 107 / bright strip 97 /
  temp slider 64 / temp strip 54 / buttons 10).
- "143 = coldest · 344 = warmest" hint removed — the strips carry the
  scale now, and they are CVD-safe (blue→amber rides a strong lightness
  contrast with an achromatic midpoint; the brightness ramp is pure
  lightness).
- Strip insets fixed: measured knob-center travel and track = the full
  slider frame (125–330), confirming the draft's 9pt inset broke the
  knob-to-color alignment at the extremes. Strips now span x=125 w=205,
  flush with the track.

## Constraints
- Single file, zero dependencies (a tiny `NSView` subclass, ~30 lines).
- Native slider look untouched (strips sit below the knobs).

## Steps — living plan
1. [x] Branch `feature/slider-gradient-guides`.
2. [x] `PresetGradientStrip` view + two strips in the manager, layout
       re-stacked (window height stays 430).
3. [x] Strip refresh on selection + both slider actions.
4. [x] Env-gated debug hooks (`KEYLIGHTBAR_DEBUG_UI`,
       `KEYLIGHTBAR_SNAPSHOT`, `KEYLIGHTBAR_DEBUG_ROW`): auto-open the
       manager on launch and render it to a PNG in-process — no
       screencapture, so no Screen Recording permission needed.
5. [x] Build clean (`make bundle`, 0 errors), screenshots light + dark +
       a Bright-preset variant, captured to
       `~/gdrive/ai-artifacts/keylightbar/` (pixel-verified strip colors).
6. [ ] Iterate on feedback; update README + push/PR when settled.

## Out of scope (this round)
- README/site copy, GIF refresh — after the design settles.
- Any change to the dot color model itself.

## Assumptions
- Screenshots go to `~/gdrive/ai-artifacts/keylightbar/` (with the capture
  script in `generators/` there), per the owner's standing artifacts rule.
- The debug hook stays env-gated and tiny; drop it before the PR if the
  owner prefers.
