# KeylightBar website

One-page site served by GitHub Pages (deployed from this `docs/` folder on `main`), reachable at <https://keylightbar.cedricscherer.com>.

- `index.html` — the page
- `scss/main.scss` — styles; compile with `npx sass scss/main.scss css/main.css --style compressed --no-source-map`
- `css/main.css` — compiled stylesheet (committed so Pages needs no build step)
- `keylightbar.gif` — demo recording (also used by the main README)

To publish changes: commit to `main` and push — Pages picks it up automatically.

Gotchas:
- After pushing, GitHub Pages rebuilds (~1 min) and caches CSS for 10 minutes —
  hard-refresh (⌘⇧R) before judging a styling change on the live site.
- Feature-card headings are measured to fit one line; if you reword one,
  check its width against the ~294px card box (longest heading should stay
  under ~200px to survive all layouts).
