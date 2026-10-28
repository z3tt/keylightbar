# KeylightBar 💡

Your [Elgato Key Light](https://www.elgato.com/key-light), in your macOS menu bar — one click to switch it on exactly how you like it, and from there it manages itself: it turns off when your Mac sleeps, comes back on when you wake it, and moves between your daytime and evening setups on schedule.

No Dock icon, no companion windows, no dependencies. Just a 💡 in your menu bar.

[![screenshot](docs/screenshot.png)](docs/screenshot.png)
*(screenshot placeholder — drop a capture of the menu bar + open preset menu at `docs/screenshot.png`)*

## What you get

- **One click to a perfect light.** Light off? Click the 🌑 and it comes on with your last-used preset. Light on? Click the 💡 for the full preset picker.
- **Your presets, built in-app.** Seven sensible presets ship with it — *Meet, Work, Bright, Cold, Warm, Night, Chill* — and you can add, rename, and tune your own with sliders. No config files, no command line.
- **A light that sleeps and wakes with your Mac.** Two independent rules you can toggle: *Off When Mac Sleeps* and *On When Mac Wakes*. This is the gap KeylightBar was born to fill — Elgato's own Control Center can switch your light off automatically, but nothing switches it back on when you return to your desk.
- **A light that knows the time.** *Time Of Day* switches between a day preset and an evening preset automatically — Work until 19:00, Chill after (presets and hours are yours to choose). It applies on its own while you work, and on wake.
- **Always in sync.** The icon and menu reflect the light's *real* state — even if you changed it from Elgato's app or the physical controls, KeylightBar keeps up.
- **Zero setup on normal networks.** It finds your light by itself; on networks where auto-discovery fails, it scans the local network and finds it anyway. And it never pretends to control what it can't reach: preset picking stays disabled until your light is actually connected.
- **Tiny and private.** One Swift file, no dependencies, and it talks only to your light over your local network.

## The trick behind the click

The menu bar icon behaves differently depending on your light's state:

| State | Click does |
| --- | --- |
| 🌑 light **off** | turns it **on** with the last-used preset |
| 💡 light **on** | opens the **preset picker** |

macOS itself won't let one menu bar item act as a *button* when you want a button and a *menu* when you want a menu — that hybrid is what got this project started, and it's still the fastest way to a good light: no click path takes more than one step.

## Install & run

Requirements: a Mac with the Swift toolchain (ships with Xcode Command Line Tools: `xcode-select --install`).

```sh
make bundle        # compiles the app and (re)builds KeylightBar.app
open KeylightBar.app
```

To start it automatically at login, add **KeylightBar.app** to *System Settings → General → Login Items & Extensions*.

### If you downloaded the app instead of building it

The binary is unsigned, so **Gatekeeper** will block the first launch. Right-click **KeylightBar.app** → **Open** → **Open** in the confirmation dialog (macOS remembers your approval afterwards). This is unavoidable without an Apple Developer ID for signing + notarization.

Also note: macOS grants **Local Network** access per binary. A freshly compiled KeylightBar needs its own permission — if commands silently do nothing, check *System Settings → Privacy & Security → Local Network* and enable KeylightBar there.

## Make it yours

Everything is adjustable from the menu bar menu itself — no source editing, no terminal.

- **Presets** — *Manage Presets…* opens a small editor: pick a preset in the table (or double-click its name to rename it), then set name, brightness (0–100), and temperature (143 = coldest, 344 = warmest) with the sliders. Names are always title-cased (e.g. "Night Mode"). Changes apply immediately and survive restarts; *Reset Defaults* restores the original seven.
- **Sleep & wake** — the *Off When Mac Sleeps* / *On When Mac Wakes* checkboxes. On wake, KeylightBar applies the time-appropriate preset if *Time Of Day* is on, otherwise your last-used one.
- **Time Of Day** — the *Switch Presets By Time* toggle plus day/evening presets and the hours they start (defaults: Work from 08:00, Chill from 19:00).

For the curious, the settings live in UserDefaults and the light's address under `keylight.host`:

```sh
defaults read com.cedricscherer.keylightbar
```

## Compatibility

KeylightBar works with all Elgato WiFi lights — **Key Light, Key Light Air, Key Light Mini, Ring Light, and Light Strip** — because they all speak the same local API. On the RGB **Light Strip**, the temperature value has no visible effect (brightness and on/off work as expected).

## For tinkerers

Two things still live in the configuration block at the top of `main.swift` (edit and rebuild):

```swift
let pollInterval: TimeInterval = 30      // state sync every N seconds

let iconOn  = "💡"                       // menubar icon while on
let iconOff = "🌑"                       // menubar icon while off
```

If a configured preset no longer exists (renamed or removed in the manager), the time switch falls back to the first preset in the list.

## Troubleshooting

- **Nothing happens on click** → check Local Network permission (see above), and that the Mac and Key Light are on the same network.
- **Icon shows 🌑 although the light is on** → the launch sync couldn't reach the light. Most common cause: a freshly compiled binary hasn't been granted *Local Network* access yet — approve it and the icon corrects itself within seconds (the app retries shortly after launch). If it stays wrong for over a minute, check the address via *Configure…*.
- **Discovery doesn't find the light** → *Find Key Light* searches twice: via Bonjour and via a scan of your local network. If both fail, the light likely isn't reachable at all — use *Configure…* and enter `IP:9123` directly.
- **Compile warnings about NetService deprecation** → expected and accepted; the API works fine and keeps the app single-file. Migrating to `NWBrowser` (Network.framework) is the modern alternative.

## License

[MIT](LICENSE) — © Cédric Scherer
