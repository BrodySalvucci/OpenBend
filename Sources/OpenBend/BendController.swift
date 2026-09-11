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

    private var motionTracker = LidMotionTracker()
    private var motionTrigger = LidMotionTrigger()
    private var projectionReference = 90.0
    private var needsRearm = true
    private enum InputMode { case sensor, manual, preview }
    private var inputMode: InputMode?
    private var lastInputAngle: Double?
    private var lastMovementAt: CFTimeInterval = 0
    private var idleCaptureTimer: Timer?

    private(set) var sensorAngle: Double = 120
    private(set) var isCapturing = false
    private(set) var captureError: String?
    private var captureTask: Task<Void, Never>?
    private var wantsFastCapture = true

    private var preview: PreviewRun?
    private var previewTimer: Timer?

    /// Fired when visibility, pause, capture or permission state changes (menu bar refresh).
    var onStateChange: (() -> Void)?

    enum HideReason { case lidOpened, settled, paused, other }

    init(settings: Settings) {
        self.settings = settings
        sensorAngle = sensor.angle
    }

    // MARK: Lifecycle

    func start() {
        setupOverlay()
        sensor.onUpdate = { [weak self] sample in
            guard let self else { return }
            sensorAngle = sample.angle
            if isFollowingSensor, inputMode == .sensor, !needsRearm {
                motionTracker.observe(angle: sample.angle, at: sample.timestamp)
            }
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
            needsRearm = true
            hideReason = .other
            if isVisible { finishHide() }
            onStateChange?()
            if !settings.isPaused { scheduleCaptureRestart(after: 1.5) }
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartCapture() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
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

    /// Follow the same relative gesture in sensor and manual modes. Scripted preview gets its
    /// own temporary baseline, then returning to the sensor learns the current physical posture.
    private func synchronizeInput(at now: CFTimeInterval) {
        guard !settings.isPaused else { needsRearm = true; return }
        let mode: InputMode = preview != nil ? .preview : (isFollowingSensor ? .sensor : .manual)
        let sample = mode == .sensor ? sensor.sample : LidAngleSensor.Sample(angle: effectiveAngle, timestamp: now)
        if needsRearm || mode != inputMode {
            motionTrigger.reset(to: sample.angle)
            motionTracker.reset(to: sample.angle, at: now)
            inputMode = mode
            lastInputAngle = sample.angle
            lastMovementAt = now
            needsRearm = false
        }
        if sample.angle != lastInputAngle {
            lastMovementAt = now
            lastInputAngle = sample.angle
        }
        motionTracker.observe(angle: sample.angle, at: sample.timestamp)
        motionTrigger.update(angle: sample.angle, activationTravel: settings.activationTravel,
                             at: now, holdDelay: settings.settleDelay, stayOnBelow: settings.stayOnBelow)
    }

    func evaluate() {
        let now = CACurrentMediaTime()
        synchronizeInput(at: now)
        let ready = isCapturing && (renderer?.hasFrame ?? false)
        let wantVisible = !settings.isPaused && ready && motionTrigger.isActive

        if wantVisible, !isVisible || isHiding {
            show(referenceAngle: motionTrigger.referenceAngle)
        } else if !wantVisible, isVisible, !isHiding {
            let reason: HideReason
            if settings.isPaused {
                reason = .paused
            } else if motionTrigger.isActive {
                reason = .other
            } else {
                reason = motionTrigger.lastRelease == .settled ? .settled : .lidOpened
            }
            beginHide(reason: reason)
        }
        claimFocusIfCommitted()
        updateCaptureRate(at: now)
    }

    /// Keyboard focus lets Esc pause mid-bend, but taking it while someone is only adjusting the
    /// lid would swallow their typing. So focus is claimed only once the lid is below the
    /// stay-on angle, where the effect holds and nobody is working.
    private func claimFocusIfCommitted() {
        guard isVisible, !isHiding, previousApp == nil, isFollowingSensor,
              sensorAngle < settings.stayOnBelow, let window else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func settingsChanged() {
        if settings.isPaused {
            needsRearm = true
            hideReason = .paused
            if isVisible { finishHide() }
            stopCapture()
        } else if !isCapturing, captureTask == nil, ScreenPermission.isGranted {
            startCapture()
        }
        evaluate()
        onStateChange?()
    }

    private func show(referenceAngle: Double) {
        guard let window, let metalView else { return }
        projectionReference = referenceAngle
        isHiding = false
        // Closing again mid-relax continues from the current tilt instead of jumping flat.
        guard !isVisible else { return }
        displayedTilt = 0
        lastTick = CACurrentMediaTime()
        isVisible = true
        // Shown without focus; claimFocusIfCommitted() takes it once the close is committed.
        window.orderFrontRegardless()
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
        if hideReason == .lidOpened, settings.soundEnabled { click.play() }
        if let previousApp, previousApp.processIdentifier != getpid() {
            previousApp.activate()
        }
        previousApp = nil
        updateCaptureRate(at: CACurrentMediaTime())
        onStateChange?()
    }

    /// Called by the renderer once per frame.
    private func frameUniforms() -> BendUniforms {
        let now = CACurrentMediaTime()
        evaluate()
        let dt = min(max(now - lastTick, 0.001), 1.0 / 20.0)
        lastTick = now

        let eye = BendMath.eye(perspective: settings.perspective, heightRatio: settings.eyeHeightRatio)
        let maxTilt = max(projectionReference - BendMath.minimumAngle(eye: eye), 1)
        // The preview is already a continuous curve. Quantized physical/manual input needs
        // reconstruction using sensor change times, independently of display frame rate.
        let angle = preview != nil ? effectiveAngle : motionTracker.value(
            at: now, smoothing: settings.smoothing, leadTime: settings.leadTime)

        if isHiding {
            // Reopening snaps clear in a few frames. Settling relaxes away over about half a
            // second, so it reads as the glass easing back onto the content.
            displayedTilt *= exp(-dt / (hideReason == .settled ? 0.14 : 0.02))
            if displayedTilt < 0.2 {
                DispatchQueue.main.async { [weak self] in
                    guard let self, isHiding else { return }
                    finishHide()
                }
            }
        } else {
            let targetTilt = min(max(projectionReference - angle, 0), maxTilt)
            // Also ease the onset if a fast sensor sample crossed more than the trigger distance.
            displayedTilt += (targetTilt - displayedTilt) * (1 - exp(-dt / 0.025))
        }

        return BendMath.uniforms(tilt: displayedTilt, clearAngle: projectionReference, eye: eye,
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
                needsRearm = true
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
        idleCaptureTimer?.invalidate()
        idleCaptureTimer = nil
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
        renderer?.reset()
        Task { await capturer.stop() }
    }

    private func restartCapture() {
        needsRearm = true
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

    private func updateCaptureRate(at now: CFTimeInterval) {
        // Warm capture on the first movement, before the relative trigger is reached. Avoid a
        // stream reconfiguration in the first visible frame; cool down only after motion stops.
        let fast = preview != nil || motionTrigger.isActive || isVisible || now - lastMovementAt < 1.0
        wantsFastCapture = fast
        let desiredRate = fast ? 60 : 10
        // Capture may have started asynchronously with an earlier idle rate. Reconcile the
        // actual stream rate too, rather than relying only on changes in our desired state.
        if isCapturing, capturer.framesPerSecond != desiredRate {
            Task { await capturer.setFrameRate(desiredRate) }
        }
        if fast, !isVisible, !motionTrigger.isActive, preview == nil, !settings.isPaused, idleCaptureTimer == nil {
            idleCaptureTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, 1.05 - (now - lastMovementAt)), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.idleCaptureTimer = nil
                    self.updateCaptureRate(at: CACurrentMediaTime())
                }
            }
        }
    }

    // MARK: Preview

    /// Plays a short scripted close-and-open so the effect can be seen without touching the lid.
    func runPreview() {
        guard !settings.isPaused, isCapturing else { return }
        preview = PreviewRun(start: CACurrentMediaTime(), startAngle: 100)
        previewTimer?.invalidate()
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
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
        let startAngle: Double
        private let closeDuration = 1.6
        private let hold = 0.7
        private let openDuration = 0.9

        func angle(at now: CFTimeInterval) -> Double {
            let t = now - start
            let low = 14.0
            func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
            if t < closeDuration {
                return startAngle + (low - startAngle) * ease(t / closeDuration)
            } else if t < closeDuration + hold {
                return low
            } else if t < closeDuration + hold + openDuration {
                let x = (t - closeDuration - hold) / openDuration
                return low + (startAngle + 4 - low) * ease(x)
            }
            return startAngle + 4
        }

        func isFinished(at now: CFTimeInterval) -> Bool {
            now - start > closeDuration + hold + openDuration + 0.05
        }
    }
}
