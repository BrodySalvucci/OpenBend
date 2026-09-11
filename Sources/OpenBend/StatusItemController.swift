import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let settings: Settings
    private let controller: BendController
    private weak var appDelegate: AppDelegate?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let angleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
    private let previewItem = NSMenuItem(title: "Preview Bend", action: #selector(preview), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Allow Screen Recording…", action: #selector(openPermission), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private var styleItems: [BendStyle: NSMenuItem] = [:]
    private var refreshTimer: Timer?

    init(settings: Settings, controller: BendController, appDelegate: AppDelegate) {
        self.settings = settings
        self.controller = controller
        self.appDelegate = appDelegate
        super.init()
        buildMenu()
        statusItem.menu = menu
        controller.onStateChange = { [weak self] in self?.updateIcon() }
        updateIcon()
    }

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        angleItem.isEnabled = false
        menu.addItem(angleItem)
        menu.addItem(.separator())

        pauseItem.target = self
        menu.addItem(pauseItem)
        previewItem.target = self
        menu.addItem(previewItem)

        let styleMenu = NSMenu()
        for style in [BendStyle.duo, .silk, .shade, .frost] {
            let item = NSMenuItem(title: style.title, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            styleMenu.addItem(item)
            styleItems[style] = item
        }
        let styleItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)
        menu.addItem(.separator())

        permissionItem.target = self
        menu.addItem(permissionItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit OpenBend", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func updateIcon() {
        let name: String
        if settings.isPaused {
            name = "laptopcomputer.slash"
        } else if controller.isVisible {
            name = "laptopcomputer.and.arrow.down"
        } else {
            name = "laptopcomputer"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "OpenBend")
            ?? NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "OpenBend")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = settings.isPaused
    }

    private func refresh() {
        if controller.sensor.isAvailable {
            angleItem.title = String(format: "Lid: %.0f°", controller.sensorAngle)
        } else {
            angleItem.title = "No lid angle sensor on this Mac"
        }
        if !ScreenPermission.isGranted {
            angleItem.title += "  ·  Screen Recording needed"
        } else if let error = controller.captureError {
            angleItem.title += "  ·  \(error)"
        }
        pauseItem.title = settings.isPaused ? "Resume" : "Pause"
        previewItem.isEnabled = !settings.isPaused && controller.isCapturing
        permissionItem.isHidden = ScreenPermission.isGranted
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        for (style, item) in styleItems {
            item.state = settings.style == style ? .on : .off
        }
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(refreshTimer!, forMode: .eventTracking)
    }

    func menuDidClose(_ menu: NSMenu) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: Actions

    @objc private func togglePause() { settings.isPaused.toggle() }
    @objc private func preview() { controller.runPreview() }
    @objc private func openSettings() { appDelegate?.showSettings() }
    @objc private func openPermission() { appDelegate?.showPermissionWindow() }
    @objc private func toggleLogin() { LaunchAtLogin.set(!LaunchAtLogin.isEnabled) }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = BendStyle(rawValue: raw) else { return }
        settings.style = style
    }
}
