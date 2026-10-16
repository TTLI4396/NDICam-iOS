import ReplayKit
import UIKit

/// ReplayKit 系统录屏 + NDI 发送
/// - 系统级采集：App 退到后台仍持续截取整屏
/// - 60Hz：ReplayKit 按屏幕刷新率回帧，NDI 声明 60fps
/// - 零拷贝中心裁剪：指针偏移到裁剪区域，整屏行距直接交 NDI
final class ScreenManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var lastError: String?
    @Published var cropSize: Int = 320

    private let recorder = RPScreenRecorder.shared()
    private let sender = NDISenderBridge()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private(set) var ndiName: String

    init(ndiName: String) {
        self.ndiName = ndiName
        super.init()
    }

    func start(ndiName: String, cropSize: Int) {
        self.ndiName = ndiName
        self.cropSize = cropSize

        guard sender.start(withName: ndiName) else {
            DispatchQueue.main.async { self.lastError = "NDI 发送器创建失败" }
            return
        }

        // 录屏期间保持后台存活
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            guard let self = self else { return }
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }

        recorder.startCapture { [weak self] sampleBuffer, bufferType, _ in
            guard bufferType == .video else { return }
            self?.processVideoFrame(sampleBuffer)
        } completionHandler: { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.lastError = "屏幕采集失败: \(error.localizedDescription)"
                    self.isRunning = false
                    self.sender.stop()
                    if self.backgroundTask != .invalid {
                        UIApplication.shared.endBackgroundTask(self.backgroundTask)
                        self.backgroundTask = .invalid
                    }
                } else {
                    self.isRunning = true
                    self.lastError = nil
                }
            }
        }
    }

    private func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let fullWidth = CVPixelBufferGetWidth(pixelBuffer)
        let fullHeight = CVPixelBufferGetHeight(pixelBuffer)
        let size = min(cropSize, min(fullWidth, fullHeight))
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let offsetX = (fullWidth - size) / 2
        let offsetY = (fullHeight - size) / 2

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let cropped = base.advanced(by: offsetY * stride + offsetX * 4)

        sender.sendVideoFrameBGRA(
            cropped.assumingMemoryBound(to: UInt8.self),
            width: Int32(size),
            height: Int32(size),
            bytesPerRow: Int32(stride),
            frameRateN: 60,
            frameRateD: 1
        )
    }

    func stop() {
        recorder.stopCapture { _ in }
        sender.stop()
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        DispatchQueue.main.async { self.isRunning = false }
    }

    deinit {
        sender.stop()
    }
}
