# Brief — Perceptual dots: resurrect the OKLCH rewrite

## Goal
Resurrect the two orphaned commits from `feature/perceptual-swatches`
(never merged: PR #11 targeted `feature/theme-harmonize`, not main) on top
of the merged slider-gradient work, so dot brightness finally reads
*perceptually*: HSB value renders saturated hues 5–10% dimmer than their
setting; OKLab lightness does not. A 50% blue preset must read exactly as
light as a 50% gray one.

## Approach
- Cherry-pick `3d00daf` (Encode swatch brightness as perceptual OKLCH
  lightness: HSB carrier → OKLab → L = 0.35...0.85, hue + chroma kept,
  chroma shrunk into sRGB) and `fe6e488` (Bright default → 100/243 ≈ 5000 K,
  the scale's neutral, so the "full brightness, neutral white" preset's dot
  is pure gray-white #cdcece instead of an honest-but-unintended blue cast).
- Conflicts resolved toward the OKLCH side: the merged HSV band
  (0.40–0.94, owner's "Bright reads dim" round of PR #13) is superseded by
  this formula — that was a stopgap; this is the proper fix. The strips and
  menu dots both re-derive automatically from `presetSwatchColor`.
- Web recompute included in the commits (dot hexes + `--preset-accent`),
  pre-verified against the app formula output compiled straight from
  `main.swift` — all fourteen match (#8b754f, #6b92c0, #7d5200, #603c02,
  #cdcece, #5283bc, #ae7117).

## Constraints
- Single file, zero dependencies — OKLab constants inline, no ColorSync.
- Cellar math verified by porting the pipeline to the contrast generator
  (`generators/dot-contrast.py`) and matching all seven hexes bit-exactly
  (one export bug found: the carrier lightness must span 0.40...0.88, not
  to 0.48 — chroma is relative to the carrier).

## Steps — living plan
1. [x] Branch `feature/perceptual-dots` from merged main.
2. [x] Cherry-pick both commits, resolve toward OKLCH; build clean.
3. [x] Formula parity: standalone Swift hex printer (extracted verbatim
       from main.swift) vs Python port — 7/7 hexes match.
4. [x] Contrast + screenshots regenerated (dots-contrast-preview.html,
       four preset-manager shots); strips verified at their rows.
5. [x] Owner live review (menubar runs this build): better overall —
       darker/more-present Bright, contrast much stronger ("barely
       visible in merged on light"). Pure gray-white Bright accepted
       as-is; no chroma nudge wanted. Ready to merge.

## Assumptions
- The OKLCH band L = 0.35...0.85 stands as designed in the original arc
  (dim never black, bright never background); the 0.94 HSV cap was the
  perceptual-lite stopgap, now retired.
- Bright preset default change only affects fresh installs; stored
  presets are untouched (UserDefaults).
