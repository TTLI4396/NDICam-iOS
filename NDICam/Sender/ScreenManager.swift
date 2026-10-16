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
    private var ciContext = CIContext()
    private var bgraBuffer: CVPixelBuffer?
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

        let fullWidth = CVPixelBufferGetWidth(pixelBuffer)
        let fullHeight = CVPixelBufferGetHeight(pixelBuffer)
        let size = min(cropSize, min(fullWidth, fullHeight))
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)

        if format == kCVPixelFormatType_32BGRA {
            // 零拷贝快路径：指针偏移裁剪
            sendBGRAFromBuffer(pixelBuffer, size: size)
        } else {
            // YCbCr 等格式：CoreImage 转 BGRA + 中心裁剪
            convertAndSend(pixelBuffer, size: size)
        }
    }

    private func sendBGRAFromBuffer(_ pixelBuffer: CVPixelBuffer, size: Int) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let fullWidth = CVPixelBufferGetWidth(pixelBuffer)
        let fullHeight = CVPixelBufferGetHeight(pixelBuffer)
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

    private func convertAndSend(_ pixelBuffer: CVPixelBuffer, size: Int) {
        prepareBGRABuffer(size: size)
        guard let dst = bgraBuffer else { return }

        let fullWidth = CVPixelBufferGetWidth(pixelBuffer)
        let fullHeight = CVPixelBufferGetHeight(pixelBuffer)
        let cropRect = CGRect(
            x: CGFloat(fullWidth - size) / 2,
            y: CGFloat(fullHeight - size) / 2,
            width: CGFloat(size),
            height: CGFloat(size)
        )

        let image = CIImage(cvPixelBuffer: pixelBuffer)
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))

        ciContext.render(
            image,
            to: dst,
            bounds: CGRect(x: 0, y: 0, width: size, height: size),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        CVPixelBufferLockBaseAddress(dst, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(dst, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(dst) else { return }

        sender.sendVideoFrameBGRA(
            base.assumingMemoryBound(to: UInt8.self),
            width: Int32(size),
            height: Int32(size),
            bytesPerRow: Int32(CVPixelBufferGetBytesPerRow(dst)),
            frameRateN: 60,
            frameRateD: 1
        )
    }

    private func prepareBGRABuffer(size: Int) {
        if let pb = bgraBuffer,
           CVPixelBufferGetWidth(pb) == size,
           CVPixelBufferGetHeight(pb) == size {
            return
        }
        bgraBuffer = nil
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault, size, size,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary, &pb
        )
        bgraBuffer = pb
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
