import AppKit
import MetalKit
import QuartzCore

/// Ties the lid sensor, the screen capture and the renderer together.
@MainActor
final class BendController {
    let settings: Settings
    let sensor = LidAngleSensor()
    let capturer = ScreenCapturer()
    private let click = ClickSound()

    private var renderer: BendRenderer?
    private var window: OverlayWindow?
    private var metalView: MTKView?
    private var previousApp: NSRunningApplication?

    private(set) var isVisible = false
    private var isHiding = false
    private var hideReason = HideReason.lidOpened
    private var displayedTilt = 0.0
    private var lastTick: CFTimeInterval = 0

    // Lid tracker. The sensor reports whole degrees, so we time the steps to estimate velocity
    // and glide continuously inside each degree instead of jumping when the reading changes.
    private var trackedRaw = 0.0
    private var lastStepTime: CFTimeInterval = 0
    private var stepVelocity = 0.0      // degrees per second, signed
    private var stepHistory: [(time: CFTimeInterval, angle: Double)] = []
    private var position = 0.0          // best estimate of the true angle
    private var displayedAngle = 0.0

    private(set) var sensorAngle: Double = 120
    private(set) var isCapturing = false
    private(set) var captureError: String?
    private var captureTask: Task<Void, Never>?
    private var wantsFastCapture = true

    private var preview: PreviewRun?
    private var previewTimer: Timer?

    /// Fired when visibility, pause, capture or permission state changes (menu bar refresh).
    var onStateChange: (() -> Void)?

    enum HideReason { case lidOpened, paused, other }

    init(settings: Settings) {
        self.settings = settings
        sensorAngle = sensor.angle
    }

    // MARK: Lifecycle

    func start() {
        setupOverlay()
        sensor.onUpdate = { [weak self] angle in
            guard let self else { return }
            sensorAngle = angle
            evaluate()
        }
        sensor.start(hertz: 120)

        settings.onChange = { [weak self] in self?.settingsChanged() }

        capturer.onFrame = { [weak self] buffer in
            guard let self, let renderer else { return }
            let isFirstFrame = !renderer.hasFrame
            renderer.submit(buffer)
            if isFirstFrame {
                Task { @MainActor in self.evaluate() }
            }
        }
        capturer.onStopped = { [weak self] error in
            guard let self else { return }
            isCapturing = false
            renderer?.reset()
            if isVisible { finishHide() }
            onStateChange?()
            if !settings.isPaused { scheduleCaptureRestart(after: 1.5) }
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restartCapture() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        }

        if ScreenPermission.isGranted {
            startCapture()
        } else {
            ScreenPermission.request()
        }
    }

    var hasScreenPermission: Bool { ScreenPermission.isGranted }

    func permissionMayHaveChanged() {
        if ScreenPermission.isGranted, !isCapturing, !settings.isPaused, captureTask == nil {
            startCapture()
        }
    }

    // MARK: Overlay

    private func setupOverlay() {
        guard let screen = NSScreen.builtIn, let device = MTLCreateSystemDefaultDevice(),
              let renderer = BendRenderer(device: device) else {
            captureError = "Metal is unavailable."
            return
        }
        self.renderer = renderer
        renderer.uniformsProvider = { [weak self] in self?.frameUniforms() ?? .identity }

        let window = OverlayWindow(screen: screen)
        window.onEscape = { [weak self] in self?.settings.isPaused = true }
        let view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: device)
        view.delegate = renderer
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = max(60, screen.maximumFramesPerSecond)
        view.enableSetNeedsDisplay = false
        view.isPaused = true
        view.autoresizingMask = [.width, .height]
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        // Two drawables instead of three: one less frame between drawing and the glass.
        (view.layer as? CAMetalLayer)?.maximumDrawableCount = 2
        window.contentView = view
        self.window = window
        self.metalView = view
    }

    private func screensChanged() {
        guard let screen = NSScreen.builtIn, let window else { return }
        window.setFrame(screen.frame, display: true)
        metalView?.preferredFramesPerSecond = max(60, screen.maximumFramesPerSecond)
        if isCapturing { restartCapture() }
    }

    // MARK: Angle model

    /// The angle that drives the effect: preview, sensor, or the manual slider.
    var effectiveAngle: Double {
        if let preview { return preview.angle(at: CACurrentMediaTime()) }
        if settings.followLid, sensor.isAvailable { return sensor.angle }   // direct read, no main-thread hop
        return settings.manualAngle
    }

    var isFollowingSensor: Bool { settings.followLid && sensor.isAvailable && preview == nil }

    func evaluate() {
        let angle = effectiveAngle
        let ready = isCapturing && (renderer?.hasFrame ?? false)
        let wantVisible = !settings.isPaused && ready && angle < settings.clearAngle

        if wantVisible, !isVisible || isHiding {
            show()
        } else if !wantVisible, isVisible, !isHiding {
            beginHide(reason: settings.isPaused ? .paused : (angle >= settings.clearAngle ? .lidOpened : .other))
        }
        updateCaptureRate(for: angle)
    }

    private func settingsChanged() {
        if settings.isPaused {
            if isVisible { beginHide(reason: .paused) }
            stopCapture()
        } else if !isCapturing, captureTask == nil, ScreenPermission.isGranted {
            startCapture()
        }
        evaluate()
        onStateChange?()
    }

    private func show() {
        guard let window, let metalView else { return }
        isHiding = false
        guard !isVisible else { return }
        displayedTilt = 0
        lastTick = CACurrentMediaTime()
        resetTracker(to: effectiveAngle, at: lastTick)
        isVisible = true
        if isFollowingSensor {
            // Take key focus so Esc can pause. We hand focus back when the desktop clears.
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
        metalView.isPaused = false
        onStateChange?()
    }

    private func beginHide(reason: HideReason) {
        guard isVisible, !isHiding else { return }
        isHiding = true
        hideReason = reason
    }

    private func finishHide() {
        guard isVisible, let window, let metalView else { return }
        window.orderOut(nil)
        metalView.isPaused = true
        isVisible = false
        isHiding = false
        displayedTilt = 0
        stepVelocity = 0
        if hideReason == .lidOpened, settings.soundEnabled { click.play() }
        if let previousApp, previousApp.processIdentifier != getpid() {
            previousApp.activate()
        }
        previousApp = nil
        onStateChange?()
    }

    private func resetTracker(to raw: Double, at now: CFTimeInterval) {
        trackedRaw = raw
        lastStepTime = now
        stepVelocity = 0
        stepHistory = [(now, raw)]
        position = raw
        displayedAngle = raw
    }

    /// Turns the stepping sensor reading into a smooth, low-latency angle.
    private func trackAngle(raw: Double, now: CFTimeInterval, dt: Double) -> Double {
        if raw != trackedRaw {
            let direction: Double = raw > trackedRaw ? 1 : -1
            // Velocity over the last ~80 ms of steps, so 60 Hz frame sampling of a 120 Hz sensor
            // doesn't alias into a frame-to-frame wobble.
            stepHistory.append((now, raw))
            stepHistory.removeAll { now - $0.time > 0.12 }
            let reference = stepHistory.first { now - $0.time >= 0.06 } ?? stepHistory.first!
            let span = now - reference.time
            let measured = span > 0.02 ? (raw - reference.angle) / span : (raw - trackedRaw) / max(now - lastStepTime, 0.002)
            stepVelocity = measured
            trackedRaw = raw
            lastStepTime = now
            // The truth just crossed into this degree at the edge it came from; keep continuity
            // when we're close, snap only if the estimate was clearly off.
            let edge = raw - 0.5 * direction
            position = min(max(position, raw - Self.trackerSlack), raw + Self.trackerSlack)
            if abs(position - edge) > Self.trackerSlack { position = edge }
        } else {
            // No new step. Once one is overdue the lid is slowing or stopped: bleed velocity off.
            let expected = 1 / max(abs(stepVelocity), 1)
            if now - lastStepTime > expected * 1.5 + 0.01 { stepVelocity *= exp(-dt / 0.03) }
            if abs(stepVelocity) < 2 { stepVelocity = 0; stepHistory = [(now, trackedRaw)] }
        }
        position += stepVelocity * dt
        position = min(max(position, trackedRaw - Self.trackerSlack), trackedRaw + Self.trackerSlack)

        // A short lead cancels part of the render latency, bounded by the slack so a lid that stops
        // dead leaves us at most a degree or so ahead. The display only ever moves in the lid's
        // direction and holds still when the lid does, so there is never a backward blip.
        var target = position + stepVelocity * max(settings.leadTime, 0)
        target = min(max(target, trackedRaw - Self.trackerSlack), trackedRaw + Self.trackerSlack)
        let next = displayedAngle + (target - displayedAngle) * (1 - exp(-dt / max(settings.smoothing, 0.004)))
        if stepVelocity < 0 {
            displayedAngle = min(displayedAngle, next)
        } else if stepVelocity > 0 {
            displayedAngle = max(displayedAngle, next)
        }
        return displayedAngle
    }

    /// How far the estimate may sit from the whole-degree reading (the reading itself is ±0.5°).
    private static let trackerSlack = 1.5

    /// Called by the renderer once per frame.
    private func frameUniforms() -> BendUniforms {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastTick, 0.001), 1.0 / 20.0)
        lastTick = now

        let eye = BendMath.eye(perspective: settings.perspective, heightRatio: settings.eyeHeightRatio)
        let maxTilt = max(settings.clearAngle - BendMath.minimumAngle(eye: eye), 1)
        let angle = trackAngle(raw: effectiveAngle, now: now, dt: dt)

        if isHiding {
            // Snap clear: collapse whatever tilt is left in a few frames, then hide.
            displayedTilt *= exp(-dt / 0.02)
            if displayedTilt < 0.2 {
                DispatchQueue.main.async { [weak self] in self?.finishHide() }
            }
        } else {
            displayedTilt = min(max(settings.clearAngle - angle, 0), maxTilt)
        }

        return BendMath.uniforms(tilt: displayedTilt, clearAngle: settings.clearAngle, eye: eye,
                                 blur: settings.blur, shadow: settings.shadow, keystone: settings.keystone,
                                 duo: settings.useDuoOptics)
    }

    // MARK: Capture

    private func startCapture() {
        guard captureTask == nil, let screen = NSScreen.builtIn else { return }
        let displayID = screen.displayID
        let scale = screen.backingScaleFactor
        let fps = wantsFastCapture ? 60 : 10
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await capturer.start(displayID: displayID, scale: scale, framesPerSecond: fps)
                isCapturing = true
                captureError = nil
            } catch {
                isCapturing = false
                captureError = error.localizedDescription
                NSLog("OpenBend: capture failed: \(error)")
                if ScreenPermission.isGranted { scheduleCaptureRestart(after: 3) }
            }
            captureTask = nil
            onStateChange?()
            evaluate()
        }
    }

    private func stopCapture() {
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
        renderer?.reset()
        Task { await capturer.stop() }
    }

    private func restartCapture() {
        guard !settings.isPaused, ScreenPermission.isGranted else { return }
        Task { [weak self] in
            guard let self else { return }
            await capturer.stop()
            isCapturing = false
            startCapture()
        }
    }

    private func scheduleCaptureRestart(after seconds: Double) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !isCapturing, captureTask == nil, !settings.isPaused else { return }
            startCapture()
        }
    }

    private func updateCaptureRate(for angle: Double) {
        // Full rate while bending or just above the clear angle; trickle otherwise.
        let fast = !isFollowingSensor || angle < settings.clearAngle + 12
        guard fast != wantsFastCapture else { return }
        wantsFastCapture = fast
        guard isCapturing else { return }
        Task { await capturer.setFrameRate(fast ? 60 : 10) }
    }

    // MARK: Preview

    /// Plays a short scripted close-and-open so the effect can be seen without touching the lid.
    func runPreview() {
        guard !settings.isPaused, isCapturing else { return }
        preview = PreviewRun(start: CACurrentMediaTime(), clearAngle: settings.clearAngle)
        previewTimer?.invalidate()
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, let preview = self.preview else { timer.invalidate(); return }
                if preview.isFinished(at: CACurrentMediaTime()) {
                    self.preview = nil
                    timer.invalidate()
                }
                self.evaluate()
            }
        }
        evaluate()
    }

    struct PreviewRun {
        let start: CFTimeInterval
        let clearAngle: Double
        private let closeDuration = 1.6
        private let hold = 0.7
        private let openDuration = 0.9

        func angle(at now: CFTimeInterval) -> Double {
            let t = now - start
            let low = 14.0
            func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
            if t < closeDuration {
                return clearAngle + (low - clearAngle) * ease(t / closeDuration)
            } else if t < closeDuration + hold {
                return low
            } else if t < closeDuration + hold + openDuration {
                let x = (t - closeDuration - hold) / openDuration
                return low + (clearAngle + 4 - low) * ease(x)
            }
            return clearAngle + 4
        }

        func isFinished(at now: CFTimeInterval) -> Bool {
            now - start > closeDuration + hold + openDuration + 0.05
        }
    }
}
