import AppKit
import ApplicationServices
import IOKit.hid
import Visualizer

private enum PreferenceKey {
    static let selectedVisualizer = "selectedVisualizer"
    static let visibleAtLaunch = "alwaysShowPrefs"
    static let displayIcon = "displayIcon"
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate {

    // MARK: - State

    private let eventTap = EventTap()
    private let mouseEventVisualizer = MouseEventVisualizer()
    private var currentVisualizer: (any Visualizer)?
    private var isCapturing: Bool = false {
        didSet { refreshStatusItemIcon() }
    }

    // MARK: - UI

    private var statusItem: NSStatusItem?
    private lazy var statusMenu: NSMenu = makeStatusMenu()
    private var preferencesWindowController: PreferencesWindowController?
    private var toggleRecordingMenuItem: NSMenuItem?
    private var trustPollTimer: Timer?

    // MARK: - Application lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[KeyCastr] applicationDidFinishLaunching")
        UserDefaultsMigration.performMigration(.standard)
        registerVisualizers()
        NSLog("[KeyCastr] registered visualizers: %@", VisualizerRegistry.availableFactories.map(\.visualizerName) as NSArray)
        registerDefaults()
        eventTap.delegate = self
        mouseEventVisualizer.delegate = self
        installStatusItem()
        loadCurrentVisualizer()
        NSLog("[KeyCastr] current visualizer: %@", currentVisualizer?.visualizerName ?? "(nil)")
        requestPermissionsAndInstallTap()
        if UserDefaults.standard.bool(forKey: PreferenceKey.visibleAtLaunch) {
            showPreferences(nil)
        }
    }

    private func requestPermissionsAndInstallTap() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let axTrusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        let inputMonitoringStatus = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        NSLog("[KeyCastr] AX trusted: %@, InputMonitoring: %d", axTrusted ? "YES" : "NO", inputMonitoringStatus.rawValue)
        if inputMonitoringStatus != kIOHIDAccessTypeGranted {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        if axTrusted && inputMonitoringStatus == kIOHIDAccessTypeGranted {
            installTapOrShowAlert()
        } else {
            NSLog("[KeyCastr] missing permissions — polling")
            startPermissionPolling()
        }
    }

    private func installTapOrShowAlert() {
        do {
            try eventTap.installTap()
            NSLog("[KeyCastr] event tap installed: %@", String(describing: eventTap.tapInstalled))
        } catch {
            NSLog("[KeyCastr] event tap install FAILED: %@", error.localizedDescription)
            presentPermissionsAlert(error: error)
        }
        isCapturing = eventTap.tapInstalled
        NSLog("[KeyCastr] isCapturing: %@", isCapturing ? "YES" : "NO")
    }

    private func startPermissionPolling() {
        trustPollTimer?.invalidate()
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted(),
                  IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else { return }
            timer.invalidate()
            Task { @MainActor in
                self?.trustPollTimer = nil
                self?.installTapOrShowAlert()
            }
        }
    }

    private func presentPermissionsAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "KeyCastr needs Accessibility and Input Monitoring access"
        alert.informativeText = "KeyCastr can't capture keystrokes without both permissions. Open System Settings → Privacy & Security and enable KeyCastr under BOTH Accessibility and Input Monitoring, then relaunch.\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Continue")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap.removeTap()
    }

    // MARK: - Setup helpers

    private func registerVisualizers() {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL else { return }
        VisualizerRegistry.loadPlugins(from: pluginsURL)
    }

    private func registerDefaults() {
        var defaults: [String: Any] = [
            PreferenceKey.displayIcon: 3,
            PreferenceKey.selectedVisualizer: "Default",
            PreferenceKey.visibleAtLaunch: true,
        ]
        for (k, v) in VisualizerRegistry.aggregatedDefaults {
            defaults[k] = v
        }
        UserDefaults.standard.register(defaults: defaults)
    }

    private func loadCurrentVisualizer() {
        let name = UserDefaults.standard.string(forKey: PreferenceKey.selectedVisualizer) ?? "Default"
        switchVisualizer(named: name)
    }

    func switchVisualizer(named name: String) {
        guard let new = VisualizerRegistry.visualizer(named: name) else {
            NSLog("[KeyCastr] no visualizer named %@", name)
            return
        }
        currentVisualizer?.deactivateVisualizer(self)
        currentVisualizer = new
        UserDefaults.standard.set(name, forKey: PreferenceKey.selectedVisualizer)
        new.showVisualizer(self)
        NSLog("[KeyCastr] switched visualizer to %@", name)
    }

    // MARK: - Status item + menu

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = statusMenu
        item.button?.image = NSImage(
            systemSymbolName: "keyboard",
            accessibilityDescription: "KeyCastr"
        )
        item.button?.image?.isTemplate = true
        statusItem = item
    }

    private func refreshStatusItemIcon() {
        let symbol = isCapturing ? "keyboard.fill" : "keyboard"
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "KeyCastr"
        )
        statusItem?.button?.image?.isTemplate = true
        toggleRecordingMenuItem?.title = isCapturing ? "Stop Casting" : "Start Casting"
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let recordItem = NSMenuItem(
            title: "Start Casting",
            action: #selector(toggleRecording(_:)),
            keyEquivalent: "k"
        )
        recordItem.keyEquivalentModifierMask = [.control, .option, .command]
        recordItem.target = self
        toggleRecordingMenuItem = recordItem
        menu.addItem(recordItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(showPreferences(_:)),
            keyEquivalent: ","
        )
        prefsItem.keyEquivalentModifierMask = [.command]
        prefsItem.target = self
        menu.addItem(prefsItem)

        let aboutItem = NSMenuItem(
            title: "About KeyCastr",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit KeyCastr",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Menu actions

    @objc func toggleRecording(_ sender: Any?) {
        isCapturing.toggle()
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(controller: self)
        }
        preferencesWindowController?.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Visualizer + display option exposure for prefs

    var availableVisualizerNames: [String] {
        VisualizerRegistry.availableFactories.map(\.visualizerName).sorted()
    }

    var currentVisualizerName: String {
        currentVisualizer?.visualizerName ?? "Default"
    }

    var currentMouseDisplayOptionIndex: Int {
        get { mouseEventVisualizer.selectedMouseDisplayOptionIndex }
        set { mouseEventVisualizer.selectedMouseDisplayOptionIndex = newValue }
    }

    var mouseDisplayOptionNames: [String] {
        mouseEventVisualizer.displayOptionNames
    }
}

// MARK: - EventTapDelegate

extension AppController: EventTapDelegate {
    func eventTap(_ tap: EventTap, noteKeystroke keystroke: Keystroke) {
        guard isCapturing else { return }
        NSLog("[KeyCastr] keystroke: %@ -> visualizer=%@", keystroke.convertToString(), currentVisualizer?.visualizerName ?? "(nil)")
        currentVisualizer?.noteKeyEvent(keystroke)
    }

    func eventTap(_ tap: EventTap, noteMouseEvent event: MouseEvent) {
        guard isCapturing else { return }
        mouseEventVisualizer.noteMouseEvent(event)
    }

    func eventTap(_ tap: EventTap, noteFlagsChanged flags: NSEvent.ModifierFlags) {
        guard isCapturing else { return }
        currentVisualizer?.noteFlagsChanged(flags)
    }
}

// MARK: - MouseEventVisualizerDelegate

extension AppController: MouseEventVisualizerDelegate {
    func mouseEventVisualizer(_ visualizer: MouseEventVisualizer, didNote event: MouseEvent) {
        currentVisualizer?.noteMouseEvent(event)
    }
}
