import Foundation
import simd

/// Which spatial model the shader draws. Carried in `BendUniforms.p3.y`.
enum BendOptics: String, CaseIterable {
    /// The whole panel is a pane of glass sliding over the held desktop (Silk, Shade, Frost).
    case glass
    /// Glass optics with a clear contact zone at the MacBook hinge and a diffusion pyramid (Duo).
    case duo
    /// Duo's optics, drawn as a lit panel standing in space: the horizontal narrowing is
    /// physically exact and, past the desktop's edge, the picture dissolves into black
    /// instead of smearing the edge pixels outward (True Duo).
    case trueDuo

    var shaderMode: Float {
        switch self {
        case .glass: 0
        case .duo: 1
        case .trueDuo: 2
        }
    }

    /// Overrides the `keystone` tuning knob. True Duo draws the narrowing exactly, which is what
    /// makes the desktop read as a panel in space; the knob only kept the others' edge spill in
    /// check, and True Duo has no spill to contain.
    var fixedKeystone: Double? { self == .trueDuo ? 1 : nil }
}

/// Per-frame shader parameters. Four float4s so the Swift and Metal layouts trivially agree.
struct BendUniforms {
    /// (physical lid angle, reference angle, eye distance, eye height) — radians and screen-height units
    var p0: SIMD4<Float>
    /// (texel width, texel height, aspect, viewport height) — filled in by the renderer
    var p1: SIMD4<Float>
    /// (blur 0..1, shadow 0..1, visibility 0..1, ramp 0..1 — how far into the travel we are)
    var p2: SIMD4<Float>
    /// (keystone 0..1, optics 0 glass / 1 Duo / 2 True Duo, unused, unused)
    var p3: SIMD4<Float>

    static let identity = BendUniforms(p0: SIMD4(.pi / 2, .pi / 2, 4, 2), p1: .zero, p2: SIMD4(0, 0, 1, 0), p3: SIMD4(0.4, 0, 0, 0))
}

/// The viewing model. Pure functions so the offline render test and the app agree exactly.
///
/// Units: the screen is 1 unit tall, the hinge is the origin, +x points at the viewer, +y is up.
/// The lid angle is measured from the keyboard: 0 closed, 90 vertical, ~120 fully open.
/// The desktop is frozen on the plane at `clearAngle` and re-projected, from a fixed eye,
/// onto the physical screen wherever it currently is. That is what makes it look like the
/// picture stays standing while the lid comes down over it.
enum BendMath {
    struct Eye {
        /// Horizontal distance from the hinge, in screen heights.
        let distance: Double
        /// Height above the keyboard plane, in screen heights.
        let height: Double
    }

    /// Perspective slider 0…1 → eye distance 8…2 screen heights, keeping the look-down angle fixed.
    static func eye(perspective: Double, heightRatio: Double) -> Eye {
        let d = 8.0 - 6.0 * min(max(perspective, 0), 1)
        return Eye(distance: d, height: d * heightRatio)
    }

    /// Below this lid angle (degrees) the screen faces away from the eye; nothing sensible to draw.
    static func minimumAngle(eye: Eye) -> Double {
        atan2(eye.height, eye.distance) * 180 / .pi + 2
    }

    /// How far (degrees) the lid can close past `clearAngle` before there is nothing left to draw.
    static func maximumTilt(clearAngle: Double, eye: Eye) -> Double {
        max(clearAngle - minimumAngle(eye: eye), 1)
    }

    /// How squarely the eye sees the physical screen: 1 head-on, 0 edge-on.
    static func viewCosine(angle: Double, eye: Eye) -> Double {
        let a = angle * .pi / 180
        let n = SIMD2(sin(a), -cos(a))                 // screen normal, toward the viewer
        let e = SIMD2(eye.distance, eye.height)
        return simd_dot(n, e) / simd_length(e)
    }

    static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Build uniforms for a lid that has closed `tilt` degrees past `clearAngle`.
    /// `keystone` is the tuning knob; an optics with its own fixed value overrides it.
    static func uniforms(tilt: Double, clearAngle: Double, eye: Eye, blur: Double, shadow: Double, keystone: Double = 0.4, optics: BendOptics = .glass) -> BendUniforms {
        let maxTilt = maximumTilt(clearAngle: clearAngle, eye: eye)
        let t = min(max(tilt, 0), maxTilt)
        let angle = clearAngle - t

        // Blur and shadow build over the first ~85% of the travel; the last stretch fades to black
        // as the panel turns edge-on to the eye.
        let ramp = smoothstep(t / (maxTilt * 0.85))
        let visibility = smoothstep(viewCosine(angle: angle, eye: eye) / 0.16)
        let k = optics.fixedKeystone ?? keystone

        return BendUniforms(
            p0: SIMD4(Float(angle * .pi / 180), Float(clearAngle * .pi / 180), Float(eye.distance), Float(eye.height)),
            p1: .zero,
            p2: SIMD4(Float(blur * ramp), Float(shadow * ramp), Float(visibility), Float(ramp)),
            p3: SIMD4(Float(min(max(k, 0), 1)), optics.shaderMode, 0, 0)
        )
    }
}
