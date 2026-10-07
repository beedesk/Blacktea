import AppKit
import ServiceManagement

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let session = AwakeSession(store: SettingsStore(), power: KeepAwake())
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem(title: "Keep Awake", action: #selector(toggleAwake), keyEquivalent: "")
    private let remainingItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let durationItem = NSMenuItem(title: "Duration", action: nil, keyEquivalent: "")
    private let displayItem = NSMenuItem(title: "Keep Display Awake", action: #selector(toggleDisplay), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private var durationItems: [NSMenuItem] = []
    private var menuRefreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bid = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bid)
               .contains(where: { $0 != NSRunningApplication.current }) {
            NSApp.terminate(nil)   // already running (e.g. a second copy)
            return
        }
        buildMenu()
        session.onChange = { [weak self] in self?.refresh() }
        session.restore()
        setupLoginItemOnFirstLaunch()
        refresh()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.power.apply(active: false, display: false)   // state stays saved for next launch
    }

    // MARK: Menu

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        menu.autoenablesItems = false

        toggleItem.target = self
        menu.addItem(toggleItem)
        remainingItem.isEnabled = false
        menu.addItem(remainingItem)

        let sub = NSMenu()
        for option in DurationOption.all {
            let item = NSMenuItem(title: option.title, action: #selector(chooseDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = option.minutes
            sub.addItem(item)
            durationItems.append(item)
        }
        durationItem.submenu = sub
        menu.addItem(durationItem)

        menu.addItem(.separator())
        displayItem.target = self
        menu.addItem(displayItem)
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit BlackTea", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func refresh() {
        guard statusItem != nil else { return }
        let active = session.isActive
        let symbol = active ? "cup.and.saucer.fill" : "cup.and.saucer"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: active ? "BlackTea: awake" : "BlackTea: off")
        image?.isTemplate = true
        statusItem.button?.image = image

        var status = "Off"
        if active {
            if let r = session.remaining() { status = "\(TimeFormat.remaining(r)) left" } else { status = "Awake indefinitely" }
        }
        statusItem.button?.toolTip = "BlackTea: \(status)"

        toggleItem.state = active ? .on : .off
        remainingItem.isHidden = !active
        remainingItem.title = active ? (session.remaining().map { "    \(TimeFormat.remaining($0)) left" } ?? "    Until turned off") : ""
        durationItem.title = "Duration: \(session.duration.title)"
        for item in durationItems { item.state = item.tag == session.duration.minutes ? .on : .off }
        displayItem.state = session.displayAwake ? .on : .off

        switch SMAppService.mainApp.status {
        case .enabled:
            loginItem.state = .on; loginItem.title = "Start at Login"
        case .requiresApproval:
            loginItem.state = .mixed; loginItem.title = "Start at Login (approve in System Settings)"
        default:
            loginItem.state = .off; loginItem.title = "Start at Login"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        session.checkExpiry()
        refresh()
        let t = Timer(timeInterval: 1, target: self, selector: #selector(menuTick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        menuRefreshTimer = t
    }

    func menuDidClose(_ menu: NSMenu) {
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
    }

    @objc private func menuTick() { session.checkExpiry(); refresh() }
    @objc private func didWake() { session.checkExpiry(); refresh() }

    // MARK: Actions

    @objc private func toggleAwake() { session.toggle() }

    /// Picking a duration (re)starts BlackTea for that long, counting from now.
    @objc private func chooseDuration(_ sender: NSMenuItem) {
        session.start(DurationOption.from(minutes: sender.tag))
    }

    @objc private func toggleDisplay() { session.setDisplayAwake(!session.displayAwake) }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        let wasOn = service.status == .enabled || service.status == .requiresApproval
        do {
            if wasOn { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("BlackTea: login item \(wasOn ? "unregister" : "register") failed: \(error)")
        }
        session.updatePrefs { $0.startAtLogin = !wasOn; $0.loginInitialized = true }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        refresh()
    }

    // MARK: Login item

    /// On first launch (default on) register as a login item. Skipped while running from a
    /// disk image or a translocated copy, so the login item points at the installed app.
    private func setupLoginItemOnFirstLaunch() {
        if UserDefaults.standard.bool(forKey: "BTSkipLoginRegistration") { return }
        let path = Bundle.main.bundlePath
        let installed = !path.hasPrefix("/Volumes/") && !path.contains("/AppTranslocation/")
        let service = SMAppService.mainApp
        let s = session.state
        guard s.startAtLogin, installed else { return }
        if !s.loginInitialized || service.status == .notRegistered {
            do { try service.register() } catch { NSLog("BlackTea: login item register failed: \(error)") }
            session.updatePrefs { $0.loginInitialized = true }
        }
    }
}
