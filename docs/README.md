# KeylightBar website

One-page site served by GitHub Pages (deployed from this `docs/` folder on `main`), reachable at <https://keylightbar.cedricscherer.com>.

- `index.html` — the page
- `scss/main.scss` — styles; the **Site styles** workflow (`.github/workflows/site-styles.yml`) compiles them automatically on every push to `main` that touches `docs/scss/` and commits the output
- `css/main.css` — compiled stylesheet (committed by CI so Pages needs no build step); for local iteration: `npx sass scss/main.scss css/main.css --style compressed --no-source-map`
- `keylightbar.gif` — demo recording (also used by the main README)

To publish changes: commit to `main` and push — Pages picks it up automatically.

Gotchas:
- After pushing, GitHub Pages rebuilds (~1 min) and caches CSS for 10 minutes —
  hard-refresh (⌘⇧R) before judging a styling change on the live site.
- Feature-card headings are measured to fit one line; if you reword one,
  check its width against the ~294px card box (longest heading should stay
  under ~200px to survive all layouts).
- The preset menu dots and the `--preset-accent` card stripes are the app's
  swatch-formula output (`presetSwatchColor` in `main.swift`: hue + chroma from the
  temperature anchors with saturation x1.8; brightness maps to perceptual OKLCH lightness L = 0.35 + 0.50·b/100).
  They are hardcoded hexes here — whenever the default presets change,
  recompute them, or the page drifts from the app. The per-theme backgrounds
  and glows are hand-picked (approach c) and only need re-tuning by eye.
