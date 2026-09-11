// Deterministic lid motion checks; no display, sensor, or screen capture needed.
// Usage: make trigger-test

private enum TriggerTestError: Error {
    case failed(String)
}

@main
private struct TriggerTests {
    private static var checks = 0

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !condition() { throw TriggerTestError.failed(message) }
    }

    private static func near(_ actual: Double, _ expected: Double) -> Bool {
        abs(actual - expected) < 0.000_001
    }

    static func main() throws {
        // Identical gestures must work from each posture, with no fixed start angle.
        for posture in [75.0, 100.0, 130.0] {
            for travel in [1.0, 3.0, 15.0] {
                var trigger = LidMotionTrigger()
                trigger.update(angle: posture, activationTravel: travel)
                try require(!trigger.isActive, "First sample must only seed the baseline")
                try require(near(trigger.baselineAngle, posture), "Baseline must start at the current posture")
                trigger.update(angle: posture - travel + 0.1, activationTravel: travel)
                try require(!trigger.isActive, "Subthreshold closing must remain inactive at \(posture)° / \(travel)°")
                trigger.update(angle: posture - travel, activationTravel: travel)
                try require(trigger.isActive, "Required travel must activate at \(posture)° / \(travel)°")
                try require(near(trigger.referenceAngle, posture - travel), "Activation must start with zero bend at the threshold")
            }
        }

        for (setting, expectedTravel) in [(0.0, 1.0), (20.0, 15.0), (Double.nan, 3.0)] {
            var bounded = LidMotionTrigger()
            bounded.reset(to: 100)
            bounded.update(angle: 100 - expectedTravel + 0.1, activationTravel: setting)
            try require(!bounded.isActive, "Out-of-range sensitivity must use its bounded or default travel")
            bounded.update(angle: 100 - expectedTravel, activationTravel: setting)
            try require(bounded.isActive && near(bounded.referenceAngle, 100 - expectedTravel), "Sensitivity must clamp to 1…15° and default to 3°")
        }

        var trigger = LidMotionTrigger()
        trigger.reset(to: 100)
        for angle in [100.0, 100.0, 99.9, 99.5, 100.2, 99.8, 98.0, 97.3] {
            trigger.update(angle: angle, activationTravel: 3)
            try require(!trigger.isActive, "Stationary samples and subthreshold jitter must not activate")
        }
        try require(near(trigger.baselineAngle, 100.2), "Inactive baseline must follow the highest opening angle")
        trigger.update(angle: 110, activationTravel: 3)
        try require(near(trigger.baselineAngle, 110), "Opening the lid must raise the baseline")
        trigger.update(angle: 107, activationTravel: 3)
        try require(trigger.isActive && near(trigger.referenceAngle, 107), "Closing from the new baseline must activate")

        // Once active, neither direction changes nor settings changes can move the reference.
        for angle in [103.0, 90.0, 95.0, 105.0, 107.0, 107.9] {
            trigger.update(angle: angle, activationTravel: 3)
            try require(trigger.isActive, "Small reversals must preserve active state until reopening hysteresis")
            try require(near(trigger.referenceAngle, 107), "Active reference must remain fixed during movement")
        }
        trigger.update(angle: 105, activationTravel: 15)
        try require(trigger.isActive && near(trigger.referenceAngle, 107), "Changing sensitivity while active must preserve the reference")
        trigger.update(angle: 106, activationTravel: 1)
        try require(trigger.isActive && near(trigger.referenceAngle, 107), "Lowering sensitivity while active must preserve the reference")
        trigger.update(angle: 108, activationTravel: 3)
        try require(!trigger.isActive, "Reopening one degree beyond the reference must deactivate")
        try require(near(trigger.baselineAngle, 108), "Rearming must use the current reopened angle")
        trigger.update(angle: 105.1, activationTravel: 3)
        try require(!trigger.isActive, "Rearmed gesture must require the full closing travel again")
        trigger.update(angle: 105, activationTravel: 3)
        try require(trigger.isActive && near(trigger.referenceAngle, 105), "A second full gesture must activate from its new baseline")

        trigger.reset(to: 75)
        try require(!trigger.isActive && near(trigger.baselineAngle, 75), "Reset must clear activation and adopt a new posture")
        trigger.update(angle: 73, activationTravel: 3)
        try require(!trigger.isActive, "Reset posture must also require the full threshold")
        trigger.update(angle: 72, activationTravel: 3)
        try require(trigger.isActive && near(trigger.referenceAngle, 72), "Reset posture must activate normally")

        // Invalid sensor samples must not accidentally activate, deactivate, or change the baseline.
        let invalidAngles: [Double] = [.nan, .infinity, -.infinity, -0.1, 180.1]
        for angle in invalidAngles {
            trigger.update(angle: angle, activationTravel: 3)
            try require(trigger.isActive && near(trigger.referenceAngle, 72), "Invalid active sample must be ignored")
        }
        trigger.reset(to: 100)
        for angle in invalidAngles {
            trigger.update(angle: angle, activationTravel: 3)
            try require(!trigger.isActive && near(trigger.baselineAngle, 100), "Invalid inactive sample must be ignored")
            trigger.reset(to: angle)
            try require(!trigger.isActive && near(trigger.baselineAngle, 100), "Invalid reset must be ignored")
        }
        var unseeded = LidMotionTrigger()
        for angle in invalidAngles { unseeded.update(angle: angle, activationTravel: 3) }
        unseeded.update(angle: 75, activationTravel: 3)
        try require(!unseeded.isActive && near(unseeded.baselineAngle, 75), "Invalid initial input must not poison the first valid sample")

        // Resting settles the effect above the stay-on angle, and never below it.
        func timed(_ trigger: inout LidMotionTrigger, _ samples: [(Double, Double)]) {
            for (time, angle) in samples {
                trigger.update(angle: angle, activationTravel: 3, at: time, holdDelay: 1.5, stayOnBelow: 70)
            }
        }

        var rest = LidMotionTrigger()
        rest.reset(to: 110)
        timed(&rest, [(0.0, 109), (0.1, 108), (0.2, 107), (0.3, 106)])
        try require(rest.isActive && near(rest.referenceAngle, 107), "Lowering the lid past the travel must activate")
        timed(&rest, [(1.0, 106), (1.79, 106)])
        try require(rest.isActive, "A rest shorter than the hold delay must keep the effect")
        timed(&rest, [(1.81, 106)])
        try require(!rest.isActive && rest.lastRelease == .settled, "Resting above the stay-on angle must settle after the delay")
        try require(near(rest.baselineAngle, 106), "Settling must learn the resting posture")
        timed(&rest, [(2.5, 104.1)])
        try require(!rest.isActive, "Closing again from a settled posture must need the full travel")
        timed(&rest, [(2.6, 103)])
        try require(rest.isActive && near(rest.referenceAngle, 103), "Closing again from a settled posture must reactivate")

        // One-step sensor flicker at rest is not movement.
        var flicker = LidMotionTrigger()
        flicker.reset(to: 100)
        timed(&flicker, [(0.0, 96)])
        try require(flicker.isActive, "Flicker test must start active")
        for (i, angle) in [95.0, 96, 95, 96, 95, 96, 95, 96].enumerated() {
            timed(&flicker, [(0.2 + Double(i) * 0.2, angle)])
        }
        timed(&flicker, [(1.75, 96)])
        try require(!flicker.isActive && flicker.lastRelease == .settled, "One-degree flicker at rest must not hold the effect open")

        // A slow, deliberate close keeps producing new lows and stays active.
        var slow = LidMotionTrigger()
        slow.reset(to: 110)
        timed(&slow, [(0.0, 107)])
        for step in 1...30 { timed(&slow, [(Double(step) * 1.2, 107 - Double(step))]) }
        try require(slow.isActive && near(slow.referenceAngle, 107), "Closing at under one degree per second must not settle mid-motion")

        // Below the stay-on angle the effect holds however long the lid rests.
        timed(&slow, [(60, 55), (120, 55), (600, 55)])
        try require(slow.isActive, "Resting below the stay-on angle must hold the effect")

        // Opening continuously from there keeps the effect until the reopen point, even across the floor.
        var t = 600.0
        var angle = 55.0
        while angle < 107.5 {
            t += 0.05; angle += 1.5
            timed(&slow, [(t, min(angle, 107.9))])
            if angle < 107.5 { try require(slow.isActive, "Opening through the stay-on angle must not settle while moving (\(angle)°)") }
        }
        timed(&slow, [(t + 0.05, 108)])
        try require(!slow.isActive && slow.lastRelease == .reopened, "Opening past the reference must reopen")

        // Raising partway and resting above the floor settles; resting just below it does not.
        var partial = LidMotionTrigger()
        partial.reset(to: 110)
        timed(&partial, [(0.0, 100), (0.5, 50), (5.0, 50), (5.2, 69), (8.0, 69)])
        try require(partial.isActive, "Resting at 69° must hold with a 70° stay-on angle")
        timed(&partial, [(8.2, 85), (9.6, 85)])
        try require(partial.isActive, "Resting above the floor must wait for the full delay")
        timed(&partial, [(9.75, 85)])
        try require(!partial.isActive && partial.lastRelease == .settled, "Raising above the floor and resting must settle")

        // Without timestamps nothing settles (the original, untimed behaviour).
        var untimed = LidMotionTrigger()
        untimed.reset(to: 110)
        for a in [106.0, 106, 106, 106] { untimed.update(angle: a, activationTravel: 3) }
        try require(untimed.isActive, "Untimed updates must never settle")

        print("Lid motion trigger: \(checks) checks passed across 75°, 100°, and 130° postures.")
    }
}
