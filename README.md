# KeylightBar 💡

A tiny, dependency-free **macOS menu bar app for the [Elgato Key Light](https://www.elgato.com/key-light)**.

One icon, right in your navbar, to control your Elgato Light:

| State | Click does |
| --- | --- |
| 🌑 light **off** | turns it **on** with the last-used preset |
| 💡 light **on** | opens a **preset picker** |

That two-state click is the whole point. macOS itself won't let one menu bar item act as a *button* when you want it to and as a *menu* when you don't — KeylightBar does.

[![screenshot](docs/screenshot.png)](docs/screenshot.png)
*(screenshot placeholder — drop a capture of the menu bar + open preset menu at `docs/screenshot.png`)*

## Features

- **Hybrid menubar icon** — off → one-click on with last preset; on → native preset menu with a ✓ on the active preset
- **7 presets** out of the box: `MEET`, `WORK`, `BRIGHT`, `COLD`, `WARM`, `NIGHT`, `CHILL` — **add, rename, and edit your own in-app** via *Manage Presets…* (no source editing, no command line)
- **Two-way discovery** — Bonjour (`_elgato._tcp`) *plus* a local subnet scan, for routers that don't propagate Bonjour advertisements (they exist — that's why the scan is there)
- **No light, no menu actions** — preset picking stays disabled until a Key Light is actually configured, so the app never pretends to control something it can't reach
- **Stays in sync** with the light's real state: at launch, every 30 s, and freshly before every menu open — even if you change the light from Elgato's own app or its physical controls
- **Remembers your last preset** across restarts
- **Sleep-aware**: turns the light off when your Mac sleeps, and picks a time-of-day preset (work by day, chill by night) on wake
- No Dock icon, no dependencies, no Xcode project — **one Swift file** compiled with plain `swiftc`

## Build & run

Requirements: macOS with the Swift toolchain (ships with Xcode Command Line Tools: `xcode-select --install`).

```sh
make bundle        # compiles main.swift and (re)builds KeylightBar.app
open KeylightBar.app
```

Or manually:

```sh
swiftc main.swift -o KeylightBar.app/Contents/MacOS/KeylightBar
open KeylightBar.app
```

To run it at login, add **KeylightBar.app** to *System Settings → General → Login Items*.

### If you downloaded the app instead of building it

The binary is unsigned, so **Gatekeeper** will block the first launch. Right-click **KeylightBar.app** → **Open** → **Open** in the confirmation dialog (macOS remembers your approval afterwards). This is unavoidable without an Apple Developer ID for signing + notarization.

Also note: macOS grants **Local Network** access per binary. A freshly compiled KeylightBar needs its own permission — if commands silently do nothing, check *System Settings → Privacy & Security → Local Network* and enable KeylightBar there.

## Configuration

### Presets

Open the menubar menu while the light is on (or anytime via *Configure…* → *Manage Presets…*) to **add, rename, remove, and edit presets**: pick a preset in the table — or double-click its name to rename it in place — then adjust name, brightness (0–100), and temperature (143 = coldest, 344 = warmest) with the sliders. Names are always uppercased. Changes apply immediately and survive restarts — they're stored in UserDefaults. *Reset Defaults* restores the original seven.

Presets live under the `keylight.presets` UserDefaults key (JSON); the Key Light address under `keylight.host`:

```sh
defaults read com.cedricscherer.keylightbar
```

### For source-level tweakers

Everything else lives in the configuration block at the top of `main.swift`. Edit and rebuild.

```swift
let pollInterval: TimeInterval = 30      // state sync every N seconds
let daytimePreset  = "WORK"              // applied on wake, 08:00–18:59
let eveningPreset = "CHILL"             // applied on wake, otherwise

let iconOn  = "💡"                       // menubar icon while on
let iconOff = "🌑"                       // menubar icon while off
```

If a configured wake preset no longer exists (renamed/removed in the manager), wake falls back to the first preset in the list.

## Troubleshooting

- **Nothing happens on click** → check Local Network permission (see above), and that the Mac and Key Light are on the same network.
- **Discovery doesn't find the light** → *Find Key Light* runs both a Bonjour search and a scan of your local subnet (every address, port 9123). If that still fails, the light likely isn't reachable at all — use *Configure…* and enter `IP:9123` directly. Both methods need the Local Network permission granted once.
- **Compile warnings about NetService deprecation** → expected and accepted; the API works fine and keeps the app single-file. Migrating to `NWBrowser` (Network.framework) is the modern alternative.

## License

[MIT](LICENSE) — © Cédric Scherer
