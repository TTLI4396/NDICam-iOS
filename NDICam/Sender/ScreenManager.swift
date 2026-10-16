import ReplayKit
import UIKit

/// 屏幕中心区域采集 + NDI 发送（ReplayKit，零拷贝裁剪）
final class ScreenManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var lastError: String?
    @Published var cropSize: Int = 320

    private let recorder = RPScreenRecorder.shared()
    private let sender = NDISenderBridge()
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

        recorder.startCapture { [weak self] sampleBuffer, bufferType, _ in
            guard bufferType == .video else { return }
            self?.processVideoFrame(sampleBuffer)
        } completionHandler: { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.lastError = "屏幕采集失败: \(error.localizedDescription)"
                    self.isRunning = false
                    self.sender.stop()
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
        // 中心裁剪：直接把指针移到裁剪区域左上角，行距保持整屏行距，无需拷贝
        let cropped = base.advanced(by: offsetY * stride + offsetX * 4)

        sender.sendVideoFrameBGRA(
            cropped.assumingMemoryBound(to: UInt8.self),
            width: Int32(size),
            height: Int32(size),
            bytesPerRow: Int32(stride),
            frameRateN: 30,
            frameRateD: 1
        )
    }

    func stop() {
        recorder.stopCapture { _ in }
        sender.stop()
        DispatchQueue.main.async { self.isRunning = false }
    }

    deinit {
        sender.stop()
    }
}
