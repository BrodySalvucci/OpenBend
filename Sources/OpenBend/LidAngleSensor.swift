import Foundation
import IOKit.hid
import QuartzCore

/// Reads the hinge angle from the lid angle sensor built into Apple silicon MacBooks.
///
/// The sensor is exposed as an Apple HID device (vendor 0x05AC, product 0x8104) on the
/// standard Sensor usage page (0x0020) with the Orientation usage (0x008A). Feature report 1
/// carries the angle in degrees as a little-endian 16-bit value at bytes 1...2.
/// 0 is closed, ~120-135 is fully open.
final class LidAngleSensor {
    private(set) var isAvailable = false
    /// Angle and monotonic change time are read together, so render cadence cannot skew velocity.
    struct Sample {
        let angle: Double
        let timestamp: TimeInterval
    }
    var sample: Sample {
        lock.lock(); defer { lock.unlock() }
        return latest
    }
    var angle: Double { sample.angle }
    private var latest = Sample(angle: 120, timestamp: CACurrentMediaTime())
    private let lock = NSLock()
    /// Called on the main thread with the original sensor timestamp whenever the angle changes.
    var onUpdate: ((Sample) -> Void)?

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var isOpen = false
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.openbend.lid-sensor", qos: .userInteractive)
    private var report = [UInt8](repeating: 0, count: 8)

    init() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            kIOHIDPrimaryUsagePageKey as String: 0x0020,
            kIOHIDPrimaryUsageKey as String: 0x008A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        self.manager = manager
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for candidate in devices {
            guard IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { continue }
            let value = Self.readAngle(from: candidate, into: &report)
            IOHIDDeviceClose(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
            if let value {
                device = candidate
                latest = Sample(angle: value, timestamp: CACurrentMediaTime())
                isAvailable = true
                break
            }
        }
    }

    deinit { stop() }

    /// Start polling at `hertz` samples per second.
    func start(hertz: Double = 120) {
        guard isAvailable, timer == nil, let device else { return }
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        isOpen = true
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / hertz, leeway: .microseconds(500))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if isOpen, let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            isOpen = false
        }
    }

    private func poll() {
        guard let device, let value = Self.readAngle(from: device, into: &report) else { return }
        lock.lock()
        let changed = value != latest.angle
        let reading = Sample(angle: value, timestamp: CACurrentMediaTime())
        if changed { latest = reading }
        lock.unlock()
        guard changed else { return }
        let callback = onUpdate
        DispatchQueue.main.async { callback?(reading) }
    }

    private static func readAngle(from device: IOHIDDevice, into buffer: inout [UInt8]) -> Double? {
        var length = CFIndex(buffer.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &buffer, &length)
        guard result == kIOReturnSuccess, length >= 3 else { return nil }
        let raw = UInt16(buffer[2]) << 8 | UInt16(buffer[1])
        return raw <= 180 ? Double(raw) : nil
    }
}
