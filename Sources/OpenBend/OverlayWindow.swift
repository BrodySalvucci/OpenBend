import AppKit

/// Borderless window that covers the built-in display above everything else while bending.
final class OverlayWindow: NSWindow {
    var onEscape: (() -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Keep the overlay out of the capture stream so it never feeds back into itself.
        // OPENBEND_CAPTURABLE=1 makes it visible to `screencapture` for debugging.
        sharingType = ProcessInfo.processInfo.environment["OPENBEND_CAPTURABLE"] == "1" ? .readOnly : .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
