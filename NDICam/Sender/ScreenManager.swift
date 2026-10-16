import UIKit
import SwiftUI
import QuartzCore

/// Apple 截图方式采集 + NDI 发送
/// CADisplayLink 60Hz 驱动 drawHierarchy，直接渲染进 CVPixelBuffer（零拷贝），
/// 中心裁剪 256/320/416，60fps BGRA NDI 发送
final class ScreenManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var lastError: String?
    @Published var cropSize: Int = 320

    private let sender = NDISenderBridge()
    private var displayLink: CADisplayLink?
    private var pixelBuffer: CVPixelBuffer?
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

        preparePixelBuffer(size: cropSize)

        let link = CADisplayLink(target: self, selector: #selector(captureFrame))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link

        DispatchQueue.main.async {
            self.isRunning = true
            self.lastError = nil
        }
    }

    private func preparePixelBuffer(size: Int) {
        if let pb = pixelBuffer,
           CVPixelBufferGetWidth(pb) == size,
           CVPixelBufferGetHeight(pb) == size {
            return
        }
        pixelBuffer = nil
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, size, size,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary, &pb
        )
        guard status == kCVReturnSuccess else {
            DispatchQueue.main.async { self.lastError = "像素缓冲区创建失败" }
            return
        }
        pixelBuffer = pb
    }

    @objc private func captureFrame() {
        guard let pb = pixelBuffer else { return }
        let size = CVPixelBufferGetWidth(pb)

        guard let window = keyWindow() else { return }
        let bounds = window.bounds

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
        let stride = CVPixelBufferGetBytesPerRow(pb)

        guard let ctx = CGContext(
            data: base,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: stride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        // 平移使窗口中心对齐裁剪区域，超出窗口部分为黑
        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.translateBy(
            x: CGFloat(size) / 2 - bounds.midX,
            y: CGFloat(size) / 2 - bounds.midY
        )
        window.drawHierarchy(in: bounds, afterScreenUpdates: false)

        sender.sendVideoFrameBGRA(
            base.assumingMemoryBound(to: UInt8.self),
            width: Int32(size),
            height: Int32(size),
            bytesPerRow: Int32(stride),
            frameRateN: 60,
            frameRateD: 1
        )
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        sender.stop()
        DispatchQueue.main.async { self.isRunning = false }
    }

    deinit {
        displayLink?.invalidate()
        sender.stop()
    }
}
