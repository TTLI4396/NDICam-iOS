import ReplayKit
import CoreImage

/// 直播扩展：系统级录屏帧 → 中心裁剪 → BGRA → NDI 60fps
/// 扩展独立进程运行，主 App 退后台后仍持续采集整屏
class SampleHandler: RPBroadcastSampleHandler {

    /// 中心裁剪边长（256 / 320 / 416；修改后需重新构建）
    private let cropSize = 320
    /// NDI 源名称
    private let ndiName = "NDICam Live"

    private let sender = NDISenderBridge()
    private var ciContext = CIContext()
    private var bgraBuffer: CVPixelBuffer?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        _ = sender.start(withName: ndiName)
    }

    override func broadcastFinished() {
        sender.stop()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let fullWidth = CVPixelBufferGetWidth(pixelBuffer)
        let fullHeight = CVPixelBufferGetHeight(pixelBuffer)
        let size = min(cropSize, min(fullWidth, fullHeight))

        if CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA {
            sendBGRAFromBuffer(pixelBuffer, size: size)
        } else {
            convertAndSend(pixelBuffer, size: size)
        }
    }

    // 零拷贝快路径
    private func sendBGRAFromBuffer(_ pixelBuffer: CVPixelBuffer, size: Int) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let offsetX = (CVPixelBufferGetWidth(pixelBuffer) - size) / 2
        let offsetY = (CVPixelBufferGetHeight(pixelBuffer) - size) / 2
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        sender.sendVideoFrameBGRA(
            base.advanced(by: offsetY * stride + offsetX * 4).assumingMemoryBound(to: UInt8.self),
            width: Int32(size),
            height: Int32(size),
            bytesPerRow: Int32(stride),
            frameRateN: 60,
            frameRateD: 1
        )
    }

    // YCbCr 等格式：CoreImage 转 BGRA + 中心裁剪
    private func convertAndSend(_ pixelBuffer: CVPixelBuffer, size: Int) {
        prepareBGRABuffer(size: size)
        guard let dst = bgraBuffer else { return }

        let cropRect = CGRect(
            x: CGFloat(CVPixelBufferGetWidth(pixelBuffer) - size) / 2,
            y: CGFloat(CVPixelBufferGetHeight(pixelBuffer) - size) / 2,
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
}
