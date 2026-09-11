import Foundation

@main
enum MotionTrackerTests {
    struct Frame {
        var time: Double
        var actual: Double
        var raw: Double
        var displayed: Double
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func simulate(duration: Double, fps: Int = 60,
                         angle: (Double) -> Double) -> [Frame] {
        var tracker = LidMotionTracker()
        var sampleAngle = angle(0).rounded()
        var sampleTime = 0.0
        tracker.reset(to: sampleAngle, at: 0)
        var result: [Frame] = []
        for tick in 1...Int(duration * 120) {
            let time = Double(tick) / 120
            let raw = angle(time).rounded()
            if raw != sampleAngle {
                sampleAngle = raw
                sampleTime = time
                tracker.observe(angle: sampleAngle, at: sampleTime)
            }
            if tick.isMultiple(of: 120 / fps) {
                // The renderer sees the same snapshot already delivered by the callback.
                tracker.observe(angle: sampleAngle, at: sampleTime)
                let displayed = tracker.value(at: time, smoothing: 0.03, leadTime: 0.03)
                result.append(Frame(time: time, actual: angle(time), raw: raw, displayed: displayed))
            }
        }
        return result
    }

    static func main() {
        for speed in [0.75, 1.5, 5.0, 30.0] {
            let duration = max(2, 8 / speed)
            let warmup = 3.5 / speed
            let frames = simulate(duration: duration) { 130 - speed * $0 }
            let steady = frames.filter { $0.time > warmup }
            let errors = steady.map { $0.displayed - $0.actual }
            let maximumError = errors.map(abs).max()!
            let maximumStepError = zip(steady, steady.dropFirst()).map {
                abs(($1.displayed - $0.displayed) + speed / 60)
            }.max()!
            let meanError = errors.reduce(0, +) / Double(errors.count)
            require(maximumError < 0.85, "\(speed)°/s tracking error: \(maximumError)")
            require(maximumStepError < 0.12, "\(speed)°/s visible stepping: \(maximumStepError)")
            require(abs(meanError) < 0.55, "\(speed)°/s mean lag: \(meanError)")

            let frames120 = simulate(duration: duration, fps: 120) { 130 - speed * $0 }
            let maximumRateDifference = steady.map { frame in
                abs(frame.displayed - frames120[Int((frame.time * 120).rounded()) - 1].displayed)
            }.max()!
            require(maximumRateDifference < 0.1, "Frame-rate-dependent motion: \(maximumRateDifference)")
            print(String(format: "PASS %5.2f°/s — max error %.3f°, step residual %.3f°, 60/120 Hz difference %.3f°",
                         speed, maximumError, maximumStepError, maximumRateDifference))
        }

        let idleStep = simulate(duration: 6) { $0 < 5 ? 110 : 109 }
        require(abs(idleStep.last!.displayed - 109) < 0.001,
                "A one-degree movement after a long idle must settle at its reading")
        require(abs(idleStep.first { $0.time >= 5.2 }!.displayed - 109) < 0.01,
                "A one-degree movement after a long idle must respond without a velocity threshold")
        print("PASS long idle followed by one degree — settles within 0.01° in 200 ms")

        let stopped = simulate(duration: 4) { 110 - min($0, 2) * 5 }
        let afterStop = stopped.filter { $0.time > 2 }
        require(afterStop.allSatisfy { abs($0.displayed - $0.raw) <= 0.751 },
                "Stopped prediction must stay within 0.75° of the sensor reading")
        require(abs(stopped.last!.displayed - stopped[stopped.count - 13].displayed) < 0.001,
                "A stationary lid must settle, not drift")
        print("PASS stop — bounded prediction and stationary output")

        let reversed = simulate(duration: 3) { time in
            time <= 1 ? 110 - time * 30 : 80 + min(time - 1, 1) * 30
        }
        let reversalStart = reversed.first { $0.time >= 1.05 }!
        let reversalEnd = reversed.first { $0.time >= 1.15 }!
        require(reversalEnd.displayed > reversalStart.displayed + 1,
                "Direction reversal must not retain the previous velocity or freeze")
        require(abs(reversalEnd.displayed - reversalEnd.actual) < 1,
                "Direction reversal must recover within 150 ms")
        let largestReversalStep = zip(reversed, reversed.dropFirst()).map {
            abs($1.displayed - $0.displayed)
        }.max()!
        require(largestReversalStep < 0.8, "Reversal should not snap: \(largestReversalStep)")
        print("PASS reversal — follows new direction within 150 ms without snapping")

        var tracker = LidMotionTracker()
        tracker.reset(to: 100, at: 10)
        tracker.observe(angle: 99, at: 11)
        tracker.observe(angle: 160, at: 9)
        tracker.observe(angle: .nan, at: 12)
        let valid = tracker.value(at: 12, smoothing: 0.03, leadTime: 0.03)
        require(valid.isFinite && abs(valid - 99) < 0.1, "Ignore stale and nonfinite samples")
        print("PASS stale and invalid samples")
    }
}
