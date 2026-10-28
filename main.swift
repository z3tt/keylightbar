// KeylightBar — a tiny, dependency-free menu bar app for the Elgato Key Light.
//
// One icon, hybrid behavior (the thing macOS menu bars don't give you for free):
//   * light off  -> click turns it ON with the last-used preset
//   * light on   -> click opens a preset picker (including "off")
//
// Extras:
//   * finds your Key Light automatically via Bonjour on first launch
//     (or set it manually via "Configure…")
//   * syncs with the light's real state at launch, every 30 s,
//     and freshly every time the menu opens
//   * remembers the last preset across restarts (UserDefaults)
//   * turns the light off on sleep, picks a time-of-day preset on wake
//
// Build:  swiftc main.swift -o KeylightBar
// Run:    ./KeylightBar   (or wrap in a KeylightBar.app bundle)
//
// Share: single file, MIT license, no dependencies beyond macOS itself.

import AppKit

// MARK: - Configuration

let presets: [(name: String, brightness: Int, temperature: Int)] = [
    ("meet",   60,  180),
    ("work",   45,  220),
    ("bright", 100, 220),
    ("cold",   50,  143),
    ("warm",   50,  344),
    ("night",  10,  220),
    ("chill",  15,  300),
]

let appVersion = "1.2"

let pollInterval: TimeInterval = 30
let daytimePreset  = "work"    // applied on wake, 08:00-18:59
let eveningPreset = "chill"   // applied on wake, otherwise

let iconOn  = "\u{1F4A1}"     // 💡
let iconOff = "\u{1F311}"     // 🌑

let hostKey = "keylight.host"          // e.g. "192.168.178.33:9123" or "Elgato Key Light.local.:9123"
let lastPresetKey = "keylight.lastPreset"

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private var browser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []

    private var currentOn     = false
    private var currentPreset: String?
    private var lastPreset   = UserDefaults.standard.string(forKey: lastPresetKey) ?? "meet"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = iconOff
        statusItem.button?.target = self
        statusItem.button?.action = #selector(iconAction(_:))

        if UserDefaults.standard.string(forKey: hostKey) == nil {
            discoverLight()
        }
        syncFromLight()

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.syncFromLight()
        }

        watchSleepAndWake()
    }

    // MARK: Click behavior (the hybrid)

    @objc private func iconAction(_ sender: Any?) {
        if currentOn {
            showPresetMenu()
        } else {
            applyPreset(lastPreset)
        }
    }

    private func showPresetMenu() {
        syncFromLight()   // fresh checkmark, fresh enabled states

        let menu = NSMenu()
        menu.autoenablesItems = false

        for preset in presets {
            let item = NSMenuItem(title: preset.name,
                                  action: #selector(presetChosen(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = preset.name
            item.state = (preset.name == currentPreset) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let off = NSMenuItem(title: "off",
                             action: #selector(turnOffViaMenu(_:)),
                             keyEquivalent: "")
        off.target = self
        off.isEnabled = currentOn
        menu.addItem(off)

        menu.addItem(.separator())

        let discover = NSMenuItem(title: "Find Key Light",
                                  action: #selector(discoverViaMenu(_:)),
                                  keyEquivalent: "")
        discover.target = self
        menu.addItem(discover)

        let configure = NSMenuItem(title: "Configure\u{2026}",
                                   action: #selector(configureViaMenu(_:)),
                                   keyEquivalent: "")
        configure.target = self
        menu.addItem(configure)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About KeylightBar",
                               action: #selector(aboutViaMenu(_:)),
                               keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit KeylightBar",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: .zero, in: button)
        }
    }

    // MARK: Menu actions

    @objc private func presetChosen(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String {
            applyPreset(name)
        }
    }

    @objc private func turnOffViaMenu(_ sender: NSMenuItem) {
        turnOff()
    }

    @objc private func discoverViaMenu(_ sender: NSMenuItem) {
        discoverLight()
    }

    @objc private func configureViaMenu(_ sender: NSMenuItem) {
        configure()
    }

    @objc private func aboutViaMenu(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "KeylightBar \(appVersion)"
        alert.informativeText = "A tiny, dependency-free menu bar app for the Elgato Key Light.\nMIT license."
        alert.runModal()
    }

    // MARK: Address: discovery + manual config

    private func discoverLight() {
        statusItem.button?.title = "\u{1F50D}"   // 🔍 while searching
        resolvingServices.removeAll()

        let b = NetServiceBrowser()
        b.delegate = self
        b.searchForServices(ofType: "_elgato._tcp.", inDomain: "")
        browser = b
    }

    private func configure() {
        let alert = NSAlert()
        alert.messageText = "Key Light address"
        alert.informativeText = "Hostname or IP of your Elgato Key Light, with port (usually 9123).\nOr choose Discover to search the network."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = UserDefaults.standard.string(forKey: hostKey) ?? ""
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discover")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let value = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty {
                UserDefaults.standard.set(value, forKey: hostKey)
                syncFromLight()
            }
        } else if response == .alertSecondButtonReturn {
            discoverLight()
        }
    }

    // MARK: State changes

    private func applyPreset(_ name: String) {
        guard let preset = presets.first(where: { $0.name == name }) else { return }
        currentOn = true
        currentPreset = name
        lastPreset = name
        UserDefaults.standard.set(name, forKey: lastPresetKey)
        updateIcon()
        api("PUT", ["numberOfLights": 1,
                    "lights": [["on": 1,
                                "brightness": preset.brightness,
                                "temperature": preset.temperature]]]) { _ in }
    }

    private func turnOff() {
        currentOn = false
        currentPreset = nil
        updateIcon()
        api("PUT", ["numberOfLights": 1, "lights": [["on": 0]]]) { _ in }
    }

    private func syncFromLight() {
        api("GET", nil) { [weak self] json in
            guard let self = self,
                  let lights = json?["lights"] as? [[String: Any]],
                  let light = lights.first else { return }

            let on = (light["on"] as? Int) == 1
            let brightness = light["brightness"] as? Int
            let temperature = light["temperature"] as? Int

            self.currentOn = on
            self.currentPreset = nil
            if on, let b = brightness, let t = temperature,
               let match = presets.first(where: { $0.brightness == b && $0.temperature == t }) {
                self.currentPreset = match.name
                self.lastPreset = match.name
                UserDefaults.standard.set(match.name, forKey: lastPresetKey)
            }
            self.updateIcon()
        }
    }

    private func updateIcon() {
        statusItem.button?.title = currentOn ? iconOn : iconOff
    }

    // MARK: Sleep / wake

    private func watchSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.turnOff()
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.wakeUp()
        }
    }

    private func wakeUp() {
        let hour = Calendar.current.component(.hour, from: Date())
        applyPreset((hour >= 8 && hour < 19) ? daytimePreset : eveningPreset)
    }

    // MARK: HTTP

    private func api(_ method: String, _ body: [String: Any]?,
                     completion: @escaping ([String: Any]?) -> Void) {
        guard let host = UserDefaults.standard.string(forKey: hostKey),
              let url = URL(string: "http://\(host)/elgato/lights") else {
            completion(nil); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 5
        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let json = ok ? (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any] : nil
            DispatchQueue.main.async { completion(json) }
        }.resume()
    }
}

// MARK: - Bonjour discovery (NetService is deprecated but battle-tested;
// MARK: it works fine and keeps this a single file with no packages)

extension AppDelegate: NetServiceBrowserDelegate, NetServiceDelegate {

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didFind service: NetService,
                           moreComing: Bool) {
        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 10)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName, !host.isEmpty else { return }
        let address = "\(host):\(sender.port)"
        UserDefaults.standard.set(address, forKey: hostKey)
        statusItem.button?.title = iconOff
        syncFromLight()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didNotSearch errorDict: [String: NSNumber]) {
        statusItem.button?.title = iconOff
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()