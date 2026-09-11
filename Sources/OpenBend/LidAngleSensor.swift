import Foundation
import IOKit.hid

/// Reads the hinge angle from the lid angle sensor built into Apple silicon MacBooks.
///
/// The sensor is exposed as an Apple HID device (vendor 0x05AC, product 0x8104) on the
/// standard Sensor usage page (0x0020) with the Orientation usage (0x008A). Feature report 1
/// carries the angle in degrees as a little-endian 16-bit value at bytes 1...2.
/// 0 is closed, ~120-135 is fully open.
final class LidAngleSensor {
    private(set) var isAvailable = false
    /// Latest reading in degrees. Safe to read from any thread (the renderer reads it at draw time).
    var angle: Double {
        lock.lock(); defer { lock.unlock() }
        return latest
    }
    private var latest: Double = 120
    private let lock = NSLock()
    /// Called on the main thread whenever the angle changes.
    var onUpdate: ((Double) -> Void)?

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
                latest = value
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
        let changed = value != latest
        latest = value
        lock.unlock()
        guard changed else { return }
        let callback = onUpdate
        DispatchQueue.main.async { callback?(value) }
    }

    private static func readAngle(from device: IOHIDDevice, into buffer: inout [UInt8]) -> Double? {
        var length = CFIndex(buffer.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &buffer, &length)
        guard result == kIOReturnSuccess, length >= 3 else { return nil }
        let raw = UInt16(buffer[2]) << 8 | UInt16(buffer[1])
        return Double(raw)
    }
}
