import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: BendController!
    private var statusItem: StatusItemController!
    private var settingsWindow: NSWindow?
    private var permissionWindow: NSWindow?
    private var permissionPoll: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = Settings.shared
        controller = BendController(settings: settings)
        statusItem = StatusItemController(settings: settings, controller: controller, appDelegate: self)
        controller.start()

        if !ScreenPermission.isGranted {
            showPermissionWindow()
        } else if ProcessInfo.processInfo.environment["OPENBEND_SHOW_SETTINGS"] == "1" {
            showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: Settings.shared, controller: controller, ui: SettingsUIState())
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "OpenBend"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("OpenBendSettings")
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showPermissionWindow() {
        if permissionWindow == nil {
            let view = PermissionView(controller: controller)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "OpenBend"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            permissionWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        permissionWindow?.makeKeyAndOrderFront(nil)

        permissionPoll?.invalidate()
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.controller.permissionMayHaveChanged()
                if self.controller.isCapturing {
                    timer.invalidate()
                    self.permissionWindow?.orderOut(nil)
                }
            }
        }
    }
}
