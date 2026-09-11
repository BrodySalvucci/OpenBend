import Foundation
import ScreenCaptureKit
import CoreMedia

/// Streams the built-in display with ScreenCaptureKit and hands each frame to `onFrame`.
final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
    /// Called on a background queue with each new BGRA frame.
    var onFrame: ((CVPixelBuffer) -> Void)?
    /// Called on the main thread if the stream stops on its own (sleep, display change).
    var onStopped: ((Error?) -> Void)?

    private var stream: SCStream?
    private var configuration = SCStreamConfiguration()
    private let sampleQueue = DispatchQueue(label: "com.openbend.capture", qos: .userInteractive)
    private(set) var isRunning = false
    private(set) var framesPerSecond = 60

    func start(displayID: CGDirectDisplayID, scale: CGFloat, framesPerSecond fps: Int) async throws {
        if stream != nil { await stop() }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let me = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 3
        config.showsCursor = false
        config.capturesAudio = false
        config.captureResolution = .best
        configuration = config
        framesPerSecond = fps

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
        isRunning = true
    }

    func setFrameRate(_ fps: Int) async {
        guard let stream, fps != framesPerSecond else { return }
        framesPerSecond = fps
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        try? await stream.updateConfiguration(configuration)
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        isRunning = false
        try? await stream.stopCapture()
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusRaw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete {
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.isRunning = false
            self.onStopped?(error)
        }
    }

    enum CaptureError: LocalizedError {
        case displayNotFound
        var errorDescription: String? { "The built-in display could not be found for capture." }
    }
}
