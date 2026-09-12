import Foundation
import Observation

enum BendStyle: String, CaseIterable, Identifiable {
    case duo, trueDuo, silk, shade, frost, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duo: "Duo"
        case .trueDuo: "True Duo"
        case .silk: "Silk"
        case .shade: "Shade"
        case .frost: "Frost"
        case .custom: "Custom"
        }
    }

    var blurb: String {
        switch self {
        case .duo: "Clear at the hinge. Soft toward the edge."
        case .trueDuo: "Creased across the middle. The top half folds down and frosts over."
        case .silk: "A clean tilt with a whisper of blur."
        case .shade: "The lid casts a shadow as it comes down."
        case .frost: "Frosted glass. The desktop softens into haze."
        case .custom: "Your own mix of the sliders."
        }
    }

    var symbol: String {
        switch self {
        case .duo: "rectangle.bottomhalf.filled"
        case .trueDuo: "rectangle.tophalf.filled"
        case .silk: "wind"
        case .shade: "moon.fill"
        case .frost: "snowflake"
        case .custom: "slider.horizontal.3"
        }
    }

    /// (perspective, blur, shadow) in 0...1.
    var preset: (Double, Double, Double)? {
        switch self {
        case .duo: (0.58, 0.85, 0.28)
        case .trueDuo: (0.58, 0.90, 0.20)
        case .silk: (0.72, 0.25, 0.25)
        case .shade: (0.75, 0.15, 0.85)
        case .frost: (0.62, 0.90, 0.30)
        case .custom: nil
        }
    }

    /// The spatial model behind a preset. Custom keeps whichever it started from.
    var optics: BendOptics? {
        switch self {
        case .duo: .duo
        case .trueDuo: .trueDuo
        case .silk, .shade, .frost: .glass
        case .custom: nil
        }
    }
}

/// User settings, persisted to UserDefaults.
@Observable
final class Settings {
    static let shared = Settings()

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var applyingPreset = false
    @ObservationIgnored private var loading = true
    /// Fired on the main thread after any change.
    @ObservationIgnored var onChange: (() -> Void)?

    var style: BendStyle { didSet { save(style.rawValue, "style"); applyPresetIfNeeded(); changed() } }
    /// The spatial model in use. A preset sets it; a slider turning that preset into a custom
    /// mix keeps it, so Duo and True Duo mixes keep their optics.
    private(set) var optics: BendOptics { didSet { save(optics.rawValue, "optics"); changed() } }
    var perspective: Double { didSet { save(perspective, "perspective"); markCustom(); changed() } }
    var blur: Double { didSet { save(blur, "blur"); markCustom(); changed() } }
    var shadow: Double { didSet { save(shadow, "shadow"); markCustom(); changed() } }
    /// Downward travel (degrees) from the open position before the effect begins.
    var activationTravel: Double { didSet { save(activationTravel, "activationTravel"); changed() } }
    /// If the lid rests above this angle, the effect relaxes away after `settleDelay`.
    /// Below it the effect holds, however long the lid rests.
    var stayOnBelow: Double { didSet { save(stayOnBelow, "stayOnBelow"); changed() } }
    /// Seconds the lid must rest before the effect relaxes away.
    var settleDelay: Double { didSet { save(settleDelay, "settleDelay"); changed() } }
    /// True: follow the hinge sensor. False: use `manualAngle`.
    var followLid: Bool { didSet { save(followLid, "followLid"); changed() } }
    var manualAngle: Double { didSet { save(manualAngle, "manualAngle"); changed() } }
    var soundEnabled: Bool { didSet { save(soundEnabled, "soundEnabled"); changed() } }
    /// Eye height as a fraction of eye distance (0.5 ≈ looking down 27° at the hinge).
    /// No UI; tune with `defaults write com.openbend.OpenBend eyeHeightRatio -float 0.6`.
    var eyeHeightRatio: Double { didSet { save(eyeHeightRatio, "eyeHeightRatio"); changed() } }
    /// How much of the perspective's horizontal narrowing to draw (1 = physically exact, 0 = none).
    /// Moderate by default; past the content's edge the diffused light spills out as a soft glow.
    /// `defaults write com.openbend.OpenBend keystone -float 0.4`.
    var keystone: Double { didSet { save(keystone, "keystone"); changed() } }
    /// Low-pass time constant for the lid angle, seconds. Smaller = quicker, steppier.
    var smoothing: Double { didSet { save(smoothing, "smoothing"); changed() } }
    /// How far ahead (seconds) to extrapolate the lid's motion to cancel pipeline latency.
    var leadTime: Double { didSet { save(leadTime, "leadTime"); changed() } }
    /// Not persisted. Pausing stops capture entirely.
    var isPaused = false { didSet { changed() } }

    private init() {
        defaults.register(defaults: [
            "style": BendStyle.duo.rawValue,
            "perspective": 0.58, "blur": 0.85, "shadow": 0.28,
            "activationTravel": 3.0, "stayOnBelow": 70.0, "settleDelay": 1.5, "followLid": true, "manualAngle": 45.0, "soundEnabled": true,
            "eyeHeightRatio": 0.5, "keystone": 0.4, "smoothing": 0.03, "leadTime": 0.03,
        ])
        let savedStyle = BendStyle(rawValue: defaults.string(forKey: "style") ?? "") ?? .duo
        style = savedStyle
        if let presetOptics = savedStyle.optics {
            optics = presetOptics
        } else if let savedOptics = defaults.string(forKey: "optics").flatMap({ BendOptics(rawValue: $0) }) {
            optics = savedOptics
        } else {
            // Before True Duo, a custom mix only remembered whether it kept Duo's optics.
            optics = defaults.bool(forKey: "useDuoOptics") ? .duo : .glass
        }
        perspective = defaults.double(forKey: "perspective")
        blur = defaults.double(forKey: "blur")
        shadow = defaults.double(forKey: "shadow")
        let savedActivationTravel = defaults.double(forKey: "activationTravel")
        activationTravel = savedActivationTravel.isFinite ? min(15, max(1, savedActivationTravel)) : 3
        let savedStayOnBelow = defaults.double(forKey: "stayOnBelow")
        stayOnBelow = savedStayOnBelow.isFinite ? min(100, max(30, savedStayOnBelow)) : 70
        let savedSettleDelay = defaults.double(forKey: "settleDelay")
        settleDelay = savedSettleDelay.isFinite ? min(5, max(0.5, savedSettleDelay)) : 1.5
        followLid = defaults.bool(forKey: "followLid")
        manualAngle = defaults.double(forKey: "manualAngle")
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        eyeHeightRatio = defaults.double(forKey: "eyeHeightRatio")
        keystone = defaults.double(forKey: "keystone")
        smoothing = defaults.double(forKey: "smoothing")
        leadTime = defaults.double(forKey: "leadTime")
        loading = false
        save(optics.rawValue, "optics")
        // Presets are tuned over time; re-apply the current one so saved slider values don't pin
        // an older tuning. Custom mixes are left alone.
        if let (p, b, sh) = style.preset {
            applyingPreset = true
            perspective = p; blur = b; shadow = sh
            applyingPreset = false
        }
    }

    private func applyPresetIfNeeded() {
        guard !loading else { return }
        if let presetOptics = style.optics { optics = presetOptics }
        guard let (p, b, s) = style.preset else { return }
        applyingPreset = true
        perspective = p
        blur = b
        shadow = s
        applyingPreset = false
    }

    private func markCustom() {
        guard !loading, !applyingPreset, style != .custom else { return }
        style = .custom
    }

    private func save(_ value: Any, _ key: String) {
        guard !loading else { return }
        defaults.set(value, forKey: key)
    }

    private func changed() {
        guard !loading else { return }
        onChange?()
    }
}
