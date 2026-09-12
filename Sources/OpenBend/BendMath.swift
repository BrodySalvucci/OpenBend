import Foundation
import simd

/// Which spatial model the shader draws. Carried in `BendUniforms.p3.y`.
enum BendOptics: String, CaseIterable {
    /// The whole panel is a pane of glass sliding over the held desktop (Silk, Shade, Frost).
    case glass
    /// Glass optics with a clear contact zone at the MacBook hinge and a diffusion pyramid (Duo).
    case duo
    /// The screen is the foldable, creased across its middle. The lower leaf stays put and
    /// sharp; the upper leaf folds toward the viewer and frosts over with a hard edge at the
    /// crease, like the folding half of the phone (True Duo).
    case trueDuo

    var shaderMode: Float {
        switch self {
        case .glass: 0
        case .duo: 1
        case .trueDuo: 2
        }
    }
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
///
/// True Duo keeps the panel itself at `clearAngle` and folds only its upper half: a leaf hinged
/// at the crease, turned toward the viewer by the tilt, cast from the same eye back onto the panel.
enum BendMath {
    struct Eye {
        /// Horizontal distance from the hinge, in screen heights.
        let distance: Double
        /// Height above the keyboard plane, in screen heights.
        let height: Double
    }

    /// Height of the True Duo crease on the panel, as a fraction of the screen height.
    static let creaseHeight = 0.5
    /// Degrees of folding over which the True Duo leaf frosts over. As on the phone, the frost is
    /// complete early; after that the leaf only foreshortens.
    static let frostTravel = 15.0

    /// Perspective slider 0…1 → eye distance 8…2 screen heights, keeping the look-down angle fixed.
    static func eye(perspective: Double, heightRatio: Double) -> Eye {
        let d = 8.0 - 6.0 * min(max(perspective, 0), 1)
        return Eye(distance: d, height: d * heightRatio)
    }

    /// Below this lid angle (degrees) the screen faces away from the eye; nothing sensible to draw.
    static func minimumAngle(eye: Eye) -> Double {
        atan2(eye.height, eye.distance) * 180 / .pi + 2
    }

    /// The True Duo crease in world units, on a panel held at `clearAngle`.
    static func crease(clearAngle: Double) -> SIMD2<Double> {
        let a0 = clearAngle * .pi / 180
        return SIMD2(creaseHeight * cos(a0), creaseHeight * sin(a0))
    }

    /// Below this leaf angle (degrees) the folded upper leaf points straight at the eye and turns
    /// edge-on; past it the eye would be looking at its back.
    static func minimumLeafAngle(clearAngle: Double, eye: Eye) -> Double {
        let c = crease(clearAngle: clearAngle)
        return atan2(eye.height - c.y, eye.distance - c.x) * 180 / .pi + 2
    }

    /// How far (degrees) the lid can close past `clearAngle` before there is nothing left to draw.
    static func maximumTilt(clearAngle: Double, eye: Eye, optics: BendOptics) -> Double {
        let floor = optics == .trueDuo ? minimumLeafAngle(clearAngle: clearAngle, eye: eye) : minimumAngle(eye: eye)
        return max(clearAngle - floor, 1)
    }

    /// How squarely the eye sees the physical screen: 1 head-on, 0 edge-on.
    static func viewCosine(angle: Double, eye: Eye) -> Double {
        let a = angle * .pi / 180
        let n = SIMD2(sin(a), -cos(a))                 // screen normal, toward the viewer
        let e = SIMD2(eye.distance, eye.height)
        return simd_dot(n, e) / simd_length(e)
    }

    /// How squarely the eye sees the folded True Duo leaf, seen from its crease: 1 head-on, 0 edge-on.
    static func leafViewCosine(angle: Double, clearAngle: Double, eye: Eye) -> Double {
        let a = angle * .pi / 180
        let n = SIMD2(sin(a), -cos(a))                 // leaf normal, toward the viewer
        let e = SIMD2(eye.distance, eye.height) - crease(clearAngle: clearAngle)
        return simd_dot(n, e) / simd_length(e)
    }

    static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Build uniforms for a lid that has closed `tilt` degrees past `clearAngle`.
    static func uniforms(tilt: Double, clearAngle: Double, eye: Eye, blur: Double, shadow: Double, keystone: Double = 0.4, optics: BendOptics = .glass) -> BendUniforms {
        let maxTilt = maximumTilt(clearAngle: clearAngle, eye: eye, optics: optics)
        let t = min(max(tilt, 0), maxTilt)
        let angle = clearAngle - t

        let ramp: Double
        let visibility: Double
        if optics == .trueDuo {
            // The upper leaf frosts over within the first few degrees of folding and then only
            // foreshortens; it goes dark as it turns edge-on to the eye.
            ramp = smoothstep(t / min(frostTravel, maxTilt * 0.85))
            visibility = smoothstep(leafViewCosine(angle: angle, clearAngle: clearAngle, eye: eye) / 0.16)
        } else {
            // Blur and shadow build over the first ~85% of the travel; the last stretch fades to black
            // as the panel turns edge-on to the eye.
            ramp = smoothstep(t / (maxTilt * 0.85))
            visibility = smoothstep(viewCosine(angle: angle, eye: eye) / 0.16)
        }

        return BendUniforms(
            p0: SIMD4(Float(angle * .pi / 180), Float(clearAngle * .pi / 180), Float(eye.distance), Float(eye.height)),
            p1: .zero,
            p2: SIMD4(Float(blur * ramp), Float(shadow * ramp), Float(visibility), Float(ramp)),
            p3: SIMD4(Float(min(max(keystone, 0), 1)), optics.shaderMode, 0, 0)
        )
    }
}
