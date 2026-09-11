import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: BendController!
    private var statusItem: StatusItemController!
    private var settingsWindow: NSWindow?
    private var permissionWindow: NSWindow?
    private var permissionPoll: Timer?
    private var onboarding: OnboardingState?

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
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
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
            let state = OnboardingState()
            onboarding = state
            let view = OnboardingView(state: state, controller: controller) { [weak self] in
                self?.closeOnboarding()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to OpenBend"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            permissionWindow = window
        }
        onboarding?.permissionGranted = ScreenPermission.isGranted
        NSApp.activate(ignoringOtherApps: true)
        permissionWindow?.makeKeyAndOrderFront(nil)

        permissionPoll?.invalidate()
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, let state = self.onboarding else { timer.invalidate(); return }
                state.permissionGranted = ScreenPermission.isGranted
                self.controller.permissionMayHaveChanged()
                state.capturing = self.controller.isCapturing
                if state.capturing, state.stage == .permission {
                    state.stage = .done
                    timer.invalidate()
                }
            }
        }
    }

    private func closeOnboarding() {
        permissionPoll?.invalidate()
        permissionPoll = nil
        permissionWindow?.orderOut(nil)
    }
}
