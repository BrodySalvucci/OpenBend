import Foundation
import AVFoundation

/// A soft, synthesized click. Generated in memory so the app ships no audio files.
final class ClickSound {
    private var player: AVAudioPlayer?

    init() {
        player = try? AVAudioPlayer(data: Self.makeWAV())
        player?.volume = 0.45
        player?.prepareToPlay()
    }

    func play() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    private static func makeWAV() -> Data {
        let sampleRate = 44_100.0
        let duration = 0.07
        let count = Int(sampleRate * duration)
        var rng = SystemRandomNumberGenerator()
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let tick = sin(2 * .pi * 2300 * t) * exp(-t / 0.0045) * 0.55
            let body = sin(2 * .pi * 820 * t) * exp(-t / 0.014) * 0.35
            let noise = (Double.random(in: -1...1, using: &rng)) * exp(-t / 0.0015) * 0.25
            let v = max(-1, min(1, tick + body + noise))
            samples[i] = Int16(v * 32_000)
        }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))                       // PCM, mono
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))  // sample rate, byte rate
        append(UInt16(2)); append(UInt16(16))                      // block align, bits
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
