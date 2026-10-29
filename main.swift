// KeylightBar — a tiny, dependency-free menu bar app for the Elgato Key Light.
//
// One icon, hybrid behavior (the thing macOS menu bars don't give you for free):
//   * light off  -> click turns it ON with the last-used preset
//   * light on   -> click opens a preset picker (including "Turn Off")
//
// Extras:
//   * finds your Key Light automatically on first launch — via Bonjour and,
//     for networks where Bonjour doesn't propagate, via a local subnet scan
//     (or set the address manually via "Configure…")
//   * presets are managed in-app via "Manage Presets…" (no source editing,
//     no command line); they persist in UserDefaults
//   * preset picking is disabled until a Key Light is actually configured
//   * syncs with the light's real state at launch, every 30 s,
//     and freshly every time the menu opens
//   * remembers the last preset across restarts (UserDefaults)
//   * sleep/wake handling as two independent rules: off when the Mac
//     sleeps, on (time-appropriate or last preset) when it wakes
//   * auto-switches between a day and an evening preset at set times
//     (on/off, presets, and hours adjustable via the "Time Of Day" menu)
//
// Build:  make bundle   (or: swiftc main.swift -o KeylightBar.app/Contents/MacOS/KeylightBar)
// Run:    open KeylightBar.app
//
// Share: single file, MIT license, no dependencies beyond macOS itself.

import AppKit

// MARK: - Configuration

let appVersion = "1.0"

let pollInterval: TimeInterval = 30
// Fallback defaults; the live values are adjustable in the "Time Of Day"
// menu (UserDefaults) and apply on wake *and* continuously while running.
let daytimePreset    = "Work"    // default day preset
let eveningPreset    = "Chill"   // default evening preset
let defaultDayStartHour    = 8    // day starts (hour)
let defaultEveningStartHour = 19   // evening starts (hour)

let iconOn  = "\u{1F4A1}"      // 💡
let iconOff = "\u{1F311}"      // 🌑

let hostKey          = "keylight.host"          // e.g. "192.168.178.33:9123" or "Elgato Key Light.local.:9123"
let lastPresetKey    = "keylight.lastPreset"
let presetsKey       = "keylight.presets"
let sleepOffKey = "keylight.sleepOff"    // turn the light off when the Mac sleeps (default: on)
let wakeOnKey   = "keylight.wakeOn"      // turn the light on when the Mac wakes (default: on)
let timeSwitchKey   = "keylight.timeSwitch"    // auto-switch presets by time of day (default: on)
let dayPresetKey    = "keylight.dayPreset"      // preset applied during day hours
let eveningPresetKey = "keylight.eveningPreset"  // preset applied during evening hours
let dayStartKey     = "keylight.dayStart"        // hour the day part begins
let eveningStartKey = "keylight.eveningStart"    // hour the evening part begins

struct Preset: Codable {
    let name: String
    let brightness: Int        // 0...100
    let temperature: Int       // 143 = coldest, 344 = warmest

    init(name: String, brightness: Int, temperature: Int) {
        self.name = name
        self.brightness = brightness
        self.temperature = temperature
    }
}

let defaultPresets: [Preset] = [
    Preset(name: "Meet",   brightness: 60,  temperature: 180),
    Preset(name: "Work",   brightness: 45,  temperature: 220),
    Preset(name: "Bright", brightness: 100, temperature: 220),
    Preset(name: "Cold",   brightness: 50,  temperature: 143),
    Preset(name: "Warm",   brightness: 50,  temperature: 344),
    Preset(name: "Night",  brightness: 10,  temperature: 220),
    Preset(name: "Chill",  brightness: 15,  temperature: 300),
]

func loadPresets() -> [Preset] {
    if let data = UserDefaults.standard.data(forKey: presetsKey),
       let decoded = try? JSONDecoder().decode([Preset].self, from: data),
       !decoded.isEmpty {
        // Title-case legacy names (earlier versions stored mixed case),
        // dropping duplicates that collide after title-casing.
        var seen = Set<String>()
        return decoded.compactMap { preset in
            let name = preset.name.capitalized
            guard !seen.contains(name) else { return nil }
            seen.insert(name)
            return Preset(name: name, brightness: preset.brightness,
                          temperature: preset.temperature)
        }
    }
    return defaultPresets
}

func savePresets(_ presets: [Preset]) {
    if let data = try? JSONEncoder().encode(presets) {
        UserDefaults.standard.set(data, forKey: presetsKey)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private var timeTimer: Timer?
    private var browser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []
    private var discoveryTimer: Timer?
    private var scanSession: URLSession?
    private var scanGeneration = 0
    private var presetManager: PresetManager?
    private var currentDayPart = 0   // 1 = day, 2 = evening, 0 = unknown

    var presets = loadPresets()
    private var currentOn     = false
    private var currentPreset: String?
    private var lastPreset   = UserDefaults.standard.string(forKey: lastPresetKey)?.capitalized

    private var isConfigured: Bool {
        UserDefaults.standard.string(forKey: hostKey) != nil
    }

    /// Turn off on sleep / turn on on wake — two independent rules.
    private var sleepOffEnabled: Bool {
        UserDefaults.standard.object(forKey: sleepOffKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: sleepOffKey)
    }

    private var wakeOnEnabled: Bool {
        UserDefaults.standard.object(forKey: wakeOnKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: wakeOnKey)
    }

    /// Auto-switch between a day and an evening preset at set times.
    private var timeSwitchEnabled: Bool {
        UserDefaults.standard.object(forKey: timeSwitchKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: timeSwitchKey)
    }

    private var dayPresetName: String {
        let name = UserDefaults.standard.string(forKey: dayPresetKey) ?? daytimePreset
        return presets.contains(where: { $0.name == name })
            ? name : (presets.first?.name ?? name)
    }

    private var eveningPresetName: String {
        let name = UserDefaults.standard.string(forKey: eveningPresetKey) ?? eveningPreset
        return presets.contains(where: { $0.name == name })
            ? name : (presets.first?.name ?? name)
    }

    private var dayStartHour: Int {
        UserDefaults.standard.object(forKey: dayStartKey) == nil
            ? defaultDayStartHour
            : UserDefaults.standard.integer(forKey: dayStartKey)
    }

    private var eveningStartHour: Int {
        UserDefaults.standard.object(forKey: eveningStartKey) == nil
            ? defaultEveningStartHour
            : UserDefaults.standard.integer(forKey: eveningStartKey)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon

        // Fixed square slot: 💡/🌑/🔍 have different glyph widths, and a
        // variable-length item would shift the neighboring menubar icons
        // every time the emoji changes.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.alignment = .center
        statusItem.button?.title = iconOff
        statusItem.button?.target = self
        statusItem.button?.action = #selector(iconAction(_:))

        if UserDefaults.standard.string(forKey: hostKey) == nil {
            discoverLight()
        }
        syncFromLight()

        // A freshly compiled binary needs its own macOS Local Network grant;
        // the launch sync races that prompt and fails silently if it hasn't
        // been granted yet. Retry briefly so the icon settles as soon as a
        // request can actually go out.
        for delay: TimeInterval in [2, 5, 10] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.syncFromLight()
            }
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.syncFromLight()
        }

        currentDayPart = dayPartNow()   // don't yank the light at launch; switch only on change
        timeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.evaluateTimeSwitch()
        }

        watchSleepAndWake()
    }

    // MARK: Click behavior (the hybrid)

    @objc private func iconAction(_ sender: Any?) {
        if currentOn || !isConfigured {
            showPresetMenu()          // unconfigured: menu shows how to fix that
        } else {
            applyPreset(lastPreset ?? presets.first?.name ?? "")
        }
    }

    private func showPresetMenu() {
        syncFromLight()   // fresh checkmark, fresh enabled states

        let menu = NSMenu()
        menu.autoenablesItems = false

        if !isConfigured {
            let hint = NSMenuItem(title: "No Key Light configured yet",
                                  action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            menu.addItem(.separator())
        }

        for preset in presets {
            let item = NSMenuItem(title: preset.name,
                                  action: #selector(presetChosen(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = preset.name
            item.isEnabled = isConfigured
            item.state = (preset.name == currentPreset) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let off = NSMenuItem(title: "Turn Off",
                             action: #selector(turnOffViaMenu(_:)),
                             keyEquivalent: "")
        off.target = self
        off.isEnabled = isConfigured && currentOn
        menu.addItem(off)

        menu.addItem(.separator())

        let sleepOff = NSMenuItem(title: "Off When Mac Sleeps",
                                  action: #selector(toggleSleepOff(_:)),
                                  keyEquivalent: "")
        sleepOff.target = self
        sleepOff.state = sleepOffEnabled ? .on : .off
        menu.addItem(sleepOff)

        let wakeOn = NSMenuItem(title: "On When Mac Wakes",
                                action: #selector(toggleWakeOn(_:)),
                                keyEquivalent: "")
        wakeOn.target = self
        wakeOn.state = wakeOnEnabled ? .on : .off
        menu.addItem(wakeOn)

        let timeOfDay = NSMenuItem(title: "Time Of Day", action: nil, keyEquivalent: "")
        timeOfDay.submenu = buildTimeMenu()
        menu.addItem(timeOfDay)

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

        let manage = NSMenuItem(title: "Manage Presets\u{2026}",
                                action: #selector(managePresetsViaMenu(_:)),
                                keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)

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

    @objc private func managePresetsViaMenu(_ sender: NSMenuItem) {
        if presetManager == nil {
            presetManager = PresetManager(app: self)
        }
        presetManager?.show()
    }

    @objc private func toggleSleepOff(_ sender: NSMenuItem) {
        UserDefaults.standard.set(!sleepOffEnabled, forKey: sleepOffKey)
        sender.state = sleepOffEnabled ? .on : .off
    }

    @objc private func toggleWakeOn(_ sender: NSMenuItem) {
        UserDefaults.standard.set(!wakeOnEnabled, forKey: wakeOnKey)
        sender.state = wakeOnEnabled ? .on : .off
    }

    // MARK: Time of day

    private func buildTimeMenu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false

        let toggle = NSMenuItem(title: "Switch Presets By Time",
                                action: #selector(toggleTimeSwitch(_:)),
                                keyEquivalent: "")
        toggle.target = self
        toggle.state = timeSwitchEnabled ? .on : .off
        m.addItem(toggle)

        m.addItem(.separator())

        m.addItem(presetSubmenu(title: "Day Preset",
                                 action: #selector(dayPresetChosen(_:)),
                                 current: dayPresetName))
        m.addItem(presetSubmenu(title: "Evening Preset",
                                 action: #selector(eveningPresetChosen(_:)),
                                 current: eveningPresetName))
        m.addItem(hourSubmenu(title: "Day Starts",
                              action: #selector(dayStartChosen(_:)),
                              current: dayStartHour, hours: 5...11))
        m.addItem(hourSubmenu(title: "Evening Starts",
                              action: #selector(eveningStartChosen(_:)),
                              current: eveningStartHour, hours: 15...23))
        return m
    }

    private func presetSubmenu(title: String, action: Selector, current: String) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title): \(current)", action: nil, keyEquivalent: "")
        let m = NSMenu()
        m.autoenablesItems = false
        for preset in presets {
            let p = NSMenuItem(title: preset.name, action: action, keyEquivalent: "")
            p.target = self
            p.representedObject = preset.name
            p.state = (preset.name == current) ? .on : .off
            m.addItem(p)
        }
        item.submenu = m
        return item
    }

    private func hourSubmenu(title: String, action: Selector, current: Int, hours: ClosedRange<Int>) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title): \(String(format: "%02d:00", current))", action: nil, keyEquivalent: "")
        let m = NSMenu()
        m.autoenablesItems = false
        for h in hours {
            let hi = NSMenuItem(title: String(format: "%02d:00", h), action: action, keyEquivalent: "")
            hi.target = self
            hi.representedObject = h
            hi.state = (h == current) ? .on : .off
            m.addItem(hi)
        }
        item.submenu = m
        return item
    }

    @objc private func toggleTimeSwitch(_ sender: NSMenuItem) {
        UserDefaults.standard.set(!timeSwitchEnabled, forKey: timeSwitchKey)
        if timeSwitchEnabled {
            evaluateTimeSwitch(force: true)
        } else {
            currentDayPart = 0
        }
    }

    @objc private func dayPresetChosen(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String {
            UserDefaults.standard.set(name, forKey: dayPresetKey)
            if timeSwitchEnabled, dayPartNow() == 1 { applyPreset(name) }
        }
    }

    @objc private func eveningPresetChosen(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String {
            UserDefaults.standard.set(name, forKey: eveningPresetKey)
            if timeSwitchEnabled, dayPartNow() == 2 { applyPreset(name) }
        }
    }

    @objc private func dayStartChosen(_ sender: NSMenuItem) {
        if let h = sender.representedObject as? Int {
            UserDefaults.standard.set(h, forKey: dayStartKey)
            evaluateTimeSwitch(force: true)
        }
    }

    @objc private func eveningStartChosen(_ sender: NSMenuItem) {
        if let h = sender.representedObject as? Int {
            UserDefaults.standard.set(h, forKey: eveningStartKey)
            evaluateTimeSwitch(force: true)
        }
    }

    /// 1 = day hours, 2 = evening/night hours.
    private func dayPartNow() -> Int {
        let hour = Calendar.current.component(.hour, from: Date())
        return (hour >= dayStartHour && hour < eveningStartHour) ? 1 : 2
    }

    /// Applies the time-appropriate preset when the day part changes.
    /// `force` also applies when the part is unchanged (wake, setting changes).
    private func evaluateTimeSwitch(force: Bool = false) {
        guard timeSwitchEnabled, isConfigured else {
            currentDayPart = 0
            return
        }
        let part = dayPartNow()
        defer { currentDayPart = part }
        guard force || part != currentDayPart else { return }
        applyPreset(part == 1 ? dayPresetName : eveningPresetName)
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

        // Backstop: reset the icon if neither method finds anything.
        discoveryTimer?.invalidate()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self = self, !self.isConfigured else { return }
            self.statusItem.button?.title = iconOff
        }

        // Method 1: Bonjour (works on well-behaved networks).
        let b = NetServiceBrowser()
        b.delegate = self
        b.searchForServices(ofType: "_elgato._tcp.", inDomain: "")
        browser = b

        // Method 2: local subnet scan (for networks where Bonjour
        // advertisements don't propagate — verified to happen).
        scanNetwork()
    }

    private func discoveryFinished() {
        discoveryTimer?.invalidate()
        browser?.stop()
        browser = nil
        scanSession?.invalidateAndCancel()
        scanSession = nil
        scanGeneration += 1   // stop any in-flight probes from claiming
        statusItem.button?.title = iconOff
        syncFromLight()
    }

    /// Probes every address on the local IPv4 subnet for an Elgato Key Light
    /// HTTP API (port 9123) and stores the first hit as the host.
    private func scanNetwork() {
        guard let local = localIPv4Address() else { return }
        let parts = local.split(separator: ".").map(String.init)
        guard parts.count == 4 else { return }
        let subnet = parts[0...2].joined(separator: ".")

        scanGeneration += 1
        let generation = scanGeneration
        scanSession?.invalidateAndCancel()

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 12
        config.httpMaximumConnectionsPerHost = 64
        let session = URLSession(configuration: config)
        scanSession = session

        let lock = NSLock()
        var pending = 254

        func probeDone() {
            lock.lock()
            pending -= 1
            let finished = pending <= 0
            lock.unlock()
            guard finished else { return }
            DispatchQueue.main.async {
                guard generation == self.scanGeneration, !self.isConfigured else { return }
                self.statusItem.button?.title = iconOff
            }
        }

        for i in 1...254 {
            guard let url = URL(string: "http://\(subnet).\(i):9123/elgato/accessory-info") else { continue }
            session.dataTask(with: url) { [weak self] data, response, _ in
                guard let self = self,
                      generation == self.scanGeneration,
                      !self.isConfigured,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      // Any Elgato light speaks this API: Key Light (Air/Mini),
                      // Ring Light, Light Strip — they all advertise "lights".
                      (json["features"] as? [String])?.contains("lights") == true else {
                    probeDone(); return
                }
                DispatchQueue.main.async {
                    guard generation == self.scanGeneration, !self.isConfigured else { return }
                    UserDefaults.standard.set("\(subnet).\(i):9123", forKey: hostKey)
                    self.discoveryFinished()
                }
                probeDone()
            }.resume()
        }
    }

    /// First non-loopback IPv4 address of this Mac (e.g. "192.168.178.20").
    private func localIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            ptr = ifa.ifa_next
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var addr = sa.pointee
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(&addr, socklen_t(addr.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if !ip.hasPrefix("127.") { return ip }
        }
        return nil
    }

    private func configure() {
        let alert = NSAlert()
        alert.messageText = "Key Light address"
        alert.informativeText = "Hostname or IP of your Elgato Key Light, with port (usually 9123).\nOr choose Discover to search the network (Bonjour + subnet scan)."
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
               let match = self.presets.first(where: { $0.brightness == b && $0.temperature == t }) {
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

    // MARK: Presets (shared with PresetManager)

    func presetsChanged() {
        savePresets(presets)
        if let last = lastPreset, !presets.contains(where: { $0.name == last }) {
            lastPreset = presets.first?.name
            if let last = lastPreset {
                UserDefaults.standard.set(last, forKey: lastPresetKey)
            }
        }
    }

    // MARK: Sleep / wake

    private func watchSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification,
                           object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.sleepOffEnabled else { return }
            self.turnOff()
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                           object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.wakeOnEnabled else { return }
            self.wakeUp()
        }
    }

    private func wakeUp() {
        applyWakePresetIfNeeded(remaining: 5)
    }

    private func wakePresetName() -> String {
        // Time-appropriate preset when time-switching is on
        // ("Bright" at 22:00 yesterday shouldn't blind you this morning),
        // otherwise the last-used preset.
        if timeSwitchEnabled {
            return dayPartNow() == 1 ? dayPresetName : eveningPresetName
        }
        return lastPreset ?? presets.first?.name ?? ""
    }

    /// Turns the light on after wake — but only if it is actually off, and
    /// with retries: right after wake the Mac's network often isn't up yet,
    /// so the first request can fail silently.
    private func applyWakePresetIfNeeded(remaining: Int) {
        api("GET", nil) { [weak self] json in
            guard let self = self, self.wakeOnEnabled, self.isConfigured else { return }
            guard let lights = json?["lights"] as? [[String: Any]],
                  let light = lights.first else {
                // Light unreachable — network probably still waking up.
                self.scheduleWakeRetry(remaining: remaining)
                return
            }
            if (light["on"] as? Int) == 1 { return }   // already on: leave it alone
            self.applyPreset(self.wakePresetName())
            self.scheduleWakeRetry(remaining: remaining)
        }
    }

    private func scheduleWakeRetry(remaining: Int) {
        guard remaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.applyWakePresetIfNeeded(remaining: remaining - 1)
        }
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
        discoveryFinished()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didNotSearch errorDict: [String: NSNumber]) {
        statusItem.button?.title = iconOff
    }
}

// MARK: - Preset manager window ("Manage Presets…")

final class PresetManager: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    private weak var app: AppDelegate!
    private var window: NSWindow!
    private var table: NSTableView!
    private var nameField: NSTextField!
    private var brightSlider: NSSlider!
    private var tempSlider: NSSlider!
    private var brightValue: NSTextField!
    private var tempValue: NSTextField!

    init(app: AppDelegate) {
        super.init()
        self.app = app

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 410, height: 430),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        window.title = "KeylightBar Presets"
        window.isReleasedWhenClosed = false
        window.center()
        let content = window.contentView!

        // Table needs 238pt of columns plus a scrollbar; 270pt keeps the
        // whole table visible without horizontal scrolling.
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 168, width: 270, height: 240))
        table = NSTableView()
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Preset"
        nameColumn.width = 110
        let brightColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("bright"))
        brightColumn.title = "Brightness"
        brightColumn.width = 70
        let tempColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("temp"))
        tempColumn.title = "Temp"
        tempColumn.width = 58
        table.addTableColumn(nameColumn)
        table.addTableColumn(brightColumn)
        table.addTableColumn(tempColumn)
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        content.addSubview(scroll)

        let add = NSButton(title: "+ Add", target: self, action: #selector(addPreset(_:)))
        add.frame = NSRect(x: 300, y: 378, width: 90, height: 30)
        content.addSubview(add)

        let remove = NSButton(title: "− Remove", target: self, action: #selector(removePreset(_:)))
        remove.frame = NSRect(x: 300, y: 343, width: 90, height: 30)
        content.addSubview(remove)

        content.addSubview(NSTextField(labelWithString: "Name:"))
        let nameLabel = content.subviews.last! as! NSTextField
        nameLabel.frame = NSRect(x: 20, y: 136, width: 60, height: 18)

        nameField = NSTextField(frame: NSRect(x: 85, y: 133, width: 305, height: 24))
        nameField.placeholderString = "preset name"
        nameField.target = self
        nameField.action = #selector(nameChanged(_:))
        content.addSubview(nameField)

        content.addSubview(NSTextField(labelWithString: "Brightness:"))
        let brightLabel = content.subviews.last! as! NSTextField
        brightLabel.frame = NSRect(x: 20, y: 102, width: 100, height: 18)

        brightSlider = NSSlider(value: 50, minValue: 0, maxValue: 100,
                                target: self, action: #selector(brightChanged(_:)))
        brightSlider.frame = NSRect(x: 125, y: 100, width: 205, height: 22)
        content.addSubview(brightSlider)
        brightValue = NSTextField(labelWithString: "50")
        brightValue.frame = NSRect(x: 335, y: 102, width: 55, height: 18)
        content.addSubview(brightValue)

        content.addSubview(NSTextField(labelWithString: "Temperature:"))
        let tempLabel = content.subviews.last! as! NSTextField
        tempLabel.frame = NSRect(x: 20, y: 68, width: 100, height: 18)

        tempSlider = NSSlider(value: 220, minValue: 143, maxValue: 344,
                              target: self, action: #selector(tempChanged(_:)))
        tempSlider.frame = NSRect(x: 125, y: 66, width: 205, height: 22)
        content.addSubview(tempSlider)
        tempValue = NSTextField(labelWithString: "220")
        tempValue.frame = NSRect(x: 335, y: 68, width: 55, height: 18)
        content.addSubview(tempValue)

        let hint = NSTextField(labelWithString: "143 = coldest \u{00B7} 344 = warmest")
        hint.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 125, y: 51, width: 220, height: 14)
        content.addSubview(hint)

        let reset = NSButton(title: "Reset Defaults", target: self, action: #selector(resetDefaults(_:)))
        reset.frame = NSRect(x: 20, y: 10, width: 130, height: 28)
        content.addSubview(reset)

        let done = NSButton(title: "Done", target: self, action: #selector(closeWindow(_:)))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.frame = NSRect(x: 310, y: 10, width: 80, height: 28)
        content.addSubview(done)
    }

    func show() {
        table.reloadData()
        if app.presets.count > 0 {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        refreshEditor()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        app.presets.count
    }

    func tableView(_ tableView: NSTableView,
                   objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let preset = app.presets[row]
        switch tableColumn?.identifier.rawValue {
        case "name":   return preset.name
        case "bright": return "\(preset.brightness)"
        case "temp":   return "\(preset.temperature)"
        default:       return nil
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        refreshEditor()
    }

    // In-table renaming: double-click the "Preset" column to edit in place.

    func tableView(_ tableView: NSTableView,
                   shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        tableColumn?.identifier.rawValue == "name"
    }

    func tableView(_ tableView: NSTableView,
                   setObjectValue object: Any?,
                   for tableColumn: NSTableColumn?, row: Int) {
        guard tableColumn?.identifier.rawValue == "name" else { return }
        renamePreset(at: row, to: object as? String ?? "")
    }

    // MARK: Editor

    private func refreshEditor() {
        let row = table.selectedRow
        guard row >= 0, row < app.presets.count else {
            nameField.stringValue = ""
            brightValue.stringValue = "-"
            tempValue.stringValue = "-"
            return
        }
        let preset = app.presets[row]
        nameField.stringValue = preset.name
        brightSlider.intValue = Int32(preset.brightness)
        tempSlider.intValue = Int32(preset.temperature)
        brightValue.stringValue = "\(preset.brightness)"
        tempValue.stringValue = "\(preset.temperature)"
    }

    private func selectedRow() -> Preset? {
        let row = table.selectedRow
        guard row >= 0, row < app.presets.count else { return nil }
        return app.presets[row]
    }

    private func commit() {
        table.reloadData()
        app.presetsChanged()
    }

    // MARK: Actions

    @objc private func nameChanged(_ sender: NSTextField) {
        renamePreset(at: table.selectedRow, to: sender.stringValue)
    }

    /// Shared validation for the name field and in-table renames:
    /// names are title-cased, never empty, never duplicates.
    private func renamePreset(at row: Int, to rawName: String) {
        guard row >= 0, row < app.presets.count else { return }
        let newName = rawName.trimmingCharacters(in: .whitespaces).capitalized
        let collides = app.presets.enumerated().contains {
            $0.offset != row && $0.element.name == newName
        }
        guard !newName.isEmpty, !collides else {
            refreshEditor()
            return
        }
        let old = app.presets[row]
        app.presets[row] = Preset(name: newName,
                                  brightness: old.brightness,
                                  temperature: old.temperature)
        commit()
    }

    @objc private func brightChanged(_ sender: NSSlider) {
        guard let preset = selectedRow() else { return }
        app.presets[table.selectedRow] = Preset(name: preset.name,
                                                 brightness: Int(sender.intValue),
                                                 temperature: preset.temperature)
        brightValue.stringValue = "\(Int(sender.intValue))"
        commit()
    }

    @objc private func tempChanged(_ sender: NSSlider) {
        guard let preset = selectedRow() else { return }
        app.presets[table.selectedRow] = Preset(name: preset.name,
                                                brightness: preset.brightness,
                                                temperature: Int(sender.intValue))
        tempValue.stringValue = "\(Int(sender.intValue))"
        commit()
    }

    @objc private func addPreset(_ sender: Any?) {
        // Ask for the name up front instead of appending a stub preset
        // that needs to be found and renamed afterwards. New presets
        // inherit the brightness/temperature of the selected one.
        let alert = NSAlert()
        alert.messageText = "New Preset"
        alert.informativeText = "Adjust brightness and temperature with the sliders afterwards."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        var n = app.presets.count + 1
        var suggestion = "Preset \(n)"
        while app.presets.contains(where: { $0.name == suggestion }) {
            n += 1
            suggestion = "Preset \(n)"
        }
        input.stringValue = suggestion
        let template = selectedRow()

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            var newName = input.stringValue.trimmingCharacters(in: .whitespaces).capitalized
            // Empty or duplicate names fall back to the unique suggestion.
            if newName.isEmpty || self.app.presets.contains(where: { $0.name == newName }) {
                newName = suggestion
            }
            self.app.presets.append(Preset(name: newName,
                                           brightness: template?.brightness ?? 50,
                                           temperature: template?.temperature ?? 220))
            self.commit()
            let idx = self.app.presets.count - 1
            self.table.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            self.table.scrollRowToVisible(idx)
        }
    }

    @objc private func removePreset(_ sender: Any?) {
        let row = table.selectedRow
        guard row >= 0, row < app.presets.count, app.presets.count > 1 else { return }
        app.presets.remove(at: row)
        commit()
        let next = min(row, app.presets.count - 1)
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        refreshEditor()
    }

    @objc private func resetDefaults(_ sender: Any?) {
        app.presets = defaultPresets
        commit()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        refreshEditor()
    }

    @objc private func closeWindow(_ sender: Any?) {
        window.orderOut(nil)
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
