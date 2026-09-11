import Foundation

/// Reconstructs motion between the lid sensor's whole-degree crossings.
/// Sample times belong to the sensor; render times only advance the display filter.
struct LidMotionTracker {
    private struct Crossing {
        var angle: Double
        var time: Double
    }

    private var raw = 0.0
    private var sampleTime = 0.0
    private var direction = 0.0
    private var velocity = 0.0
    private var crossings: [Crossing] = []
    private var displayed = 0.0
    private var previousTarget = 0.0
    private var renderTime = 0.0
    private var initialized = false

    mutating func reset(to angle: Double, at time: Double) {
        guard angle.isFinite, time.isFinite else { return }
        raw = angle
        sampleTime = time
        direction = 0
        velocity = 0
        crossings.removeAll(keepingCapacity: true)
        displayed = angle
        previousTarget = angle
        renderTime = time
        initialized = true
    }

    mutating func observe(angle: Double, at time: Double) {
        guard angle.isFinite, time.isFinite else { return }
        guard initialized else { reset(to: angle, at: time); return }
        // A frame can reread a sample already delivered through the sensor callback.
        guard time > sampleTime, angle != raw else { return }

        let nextDirection = angle > raw ? 1.0 : -1.0
        let gap = time - sampleTime
        let expectedPeriod = velocity == 0 ? Double.infinity : 1 / abs(velocity)
        let resumedAfterStop = gap > max(0.15, expectedPeriod * 2.5)
        if nextDirection != direction || resumedAfterStop {
            crossings.removeAll(keepingCapacity: true)
            velocity = 0
        }
        direction = nextDirection
        raw = angle
        sampleTime = time
        crossings.append(Crossing(angle: angle, time: time))
        if crossings.count > 4 { crossings.removeFirst(crossings.count - 4) }

        // Retain crossings, rather than a fixed time window: slow, deliberate movement
        // can take more than a second per degree and still needs continuous motion.
        if let first = crossings.first, crossings.count >= 2 {
            let elapsed = time - first.time
            if elapsed > 0 { velocity = (angle - first.angle) / elapsed }
        }
    }

    mutating func value(at time: Double, smoothing: Double, leadTime: Double) -> Double {
        guard initialized, time.isFinite else { return displayed }
        let elapsed = time - renderTime
        guard elapsed > 0 else { return displayed }

        var target = raw
        if velocity != 0 {
            // A changed rounded reading identifies the boundary it just crossed.
            // Continue through this bin at the measured cadence, with a small bounded
            // lead. If the lid stops, the estimate settles within 0.75° of its reading.
            let age = max(0, time - sampleTime)
            let lead = leadTime.isFinite ? min(max(leadTime, 0), 0.1) : 0
            target = raw - direction * 0.5 + velocity * (age + lead)
            target = min(max(target, raw - 0.75), raw + 0.75)
        }

        let tau = smoothing.isFinite ? max(smoothing, 0.004) : 0.03
        let decay = exp(-elapsed / tau)
        // Integrate a linearly moving target, avoiding the extra half-frame lead of
        // an end-of-frame lerp. The same sensor samples look alike at 60 and 120 Hz.
        let targetVelocity = (target - previousTarget) / elapsed
        displayed = target - targetVelocity * tau
            + (displayed - previousTarget + targetVelocity * tau) * decay
        previousTarget = target
        renderTime = time
        return displayed
    }
}
