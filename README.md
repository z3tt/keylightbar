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
- **7 presets** out of the box: `meet`, `work`, `bright`, `cold`, `warm`, `night`, `chill`
- **Bonjour auto-discovery** (`_elgato._tcp`) on first launch, or set the address manually via *Configure…*
- **Stays in sync** with the light's real state: at launch, every 30 s, and freshly before every menu open — even if you change the light from Elgato's own app or its physical controls
- **Remembers your last preset** across restarts
- **Sleep-aware**: turns the light off when your Mac sleeps, and picks a time-of-day preset (work by day, chill by night) on wake
- No Dock icon, no dependencies, no Xcode project — **one Swift file** (~330 lines) compiled with plain `swiftc`

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

Everything lives in the configuration block at the top of `main.swift`. Edit and rebuild.

```swift
let presets: [(name: String, brightness: Int, temperature: Int)] = [
    ("meet",   60,  180),   // (name, brightness 0–100, temperature 143–344)
    ("work",   45,  220),
    ("bright", 100, 220),
    ("cold",   50,  143),   // 143 = coldest, 344 = warmest
    ("warm",   50,  344),
    ("night",  10,  220),
    ("chill",  15,  300),
]

let pollInterval: TimeInterval = 30      // state sync every N seconds
let daytimePreset  = "work"              // applied on wake, 08:00–18:59
let eveningPreset = "chill"             // applied on wake, otherwise

let iconOn  = "💡"                       // menubar icon while on
let iconOff = "🌑"                       // menubar icon while off
```

The Key Light's address (found via discovery or entered via *Configure…*) is stored in UserDefaults under `keylight.host`, e.g. `192.168.178.33:9123`. Inspect with:

```sh
defaults read com.cedricscherer.keylightbar
```

## Troubleshooting

- **Nothing happens on click** → check Local Network permission (see above), and that the Mac and Key Light are on the same network.
- **Discovery doesn't find the light** → some routers don't propagate Bonjour/mDNS advertisements. Use the menu: *Configure…* and enter `IP:9123` directly (the port is printed on the Key Light's accessory settings or discoverable via the Elgato Control Center app).
- **Compile warnings about NetService deprecation** → expected and accepted; the API works fine and keeps the app single-file. Migrating to `NWBrowser` (Network.framework) is the modern alternative.

## License

[MIT](LICENSE) — © Cédric Scherer
