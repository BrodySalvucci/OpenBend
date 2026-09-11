import Foundation

/// Detects a closing gesture relative to the user's open posture, without an absolute angle.
///
/// Once active, the effect ends in one of two ways:
/// - **Reopened**: the lid comes back up one degree past where the effect started.
/// - **Settled**: the lid has come to rest for `holdDelay` seconds at or above `stayOnBelow`
///   degrees, so someone who only wanted the screen a little lower can keep working.
///   Below `stayOnBelow` the effect holds however long the lid rests; nobody works there.
struct LidMotionTrigger {
    enum Release { case reopened, settled }

    private(set) var isActive = false
    private(set) var baselineAngle = 0.0
    private(set) var referenceAngle = 0.0
    /// Why the most recent activation ended; nil while active or before the first one.
    private(set) var lastRelease: Release?
    private var initialized = false

    // Rest detection while active.
    private var lowestAngle = 0.0
    private var restAnchor = 0.0
    private var lastMovementTime: Double?

    /// Whole-degree readings can flicker by one step at rest; only a two-degree move away from
    /// the resting angle counts as the lid moving again. Every new low counts, so a slow,
    /// deliberate close keeps the effect alive.
    private static let restTolerance = 2.0

    mutating func reset(to angle: Double) {
        guard angle.isFinite, (0...180).contains(angle) else { return }
        initialized = true
        isActive = false
        baselineAngle = angle
        referenceAngle = angle
        lastRelease = nil
        lastMovementTime = nil
    }

    /// - Parameters:
    ///   - time: Monotonic seconds. Without it, resting never settles the effect.
    ///   - holdDelay: Seconds at rest before the effect settles.
    ///   - stayOnBelow: Lid angle below which resting never settles the effect.
    mutating func update(angle: Double, activationTravel: Double,
                         at time: Double? = nil, holdDelay: Double = 1.5, stayOnBelow: Double = 70) {
        guard angle.isFinite, (0...180).contains(angle) else { return }
        guard initialized else { reset(to: angle); return }
        let travel = activationTravel.isFinite ? min(max(activationTravel, 1), 15) : 3
        if isActive {
            // Keep the projection plane fixed through stops, reversals and tuning changes.
            // A one-degree reopening buffer prevents whole-degree sensor noise from flickering.
            if angle >= referenceAngle + 1 {
                release(.reopened, at: angle)
                return
            }
            guard let time, time.isFinite else { return }
            if angle < lowestAngle || abs(angle - restAnchor) >= Self.restTolerance {
                lowestAngle = min(lowestAngle, angle)
                restAnchor = angle
                lastMovementTime = time
            }
            let delay = holdDelay.isFinite ? max(holdDelay, 0.1) : 1.5
            let floor = stayOnBelow.isFinite ? stayOnBelow : 70
            if angle >= floor, let moved = lastMovementTime, time - moved >= delay {
                release(.settled, at: angle)
            }
        } else {
            baselineAngle = max(baselineAngle, angle)
            if baselineAngle - angle >= travel {
                referenceAngle = baselineAngle - travel
                isActive = true
                lastRelease = nil
                lowestAngle = angle
                restAnchor = angle
                lastMovementTime = time
            }
        }
    }

    private mutating func release(_ reason: Release, at angle: Double) {
        isActive = false
        lastRelease = reason
        // Learn this posture: closing further from here needs the full travel again.
        baselineAngle = angle
        lastMovementTime = nil
    }
}
