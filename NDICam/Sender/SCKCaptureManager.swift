import ScreenCaptureKit
import CoreImage
import UIKit

/// iPadOS 27+ ScreenCaptureKit 全屏采集 + NDI 发送
/// 配合 Info.plist 的 screen-capture 后台模式：退后台/切 App 持续采集整屏
@available(iOS 27.0, *)
final class SCKCaptureManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var lastError: String?

    private let sender = NDISenderBridge()
    private var stream: SCStream?
    private var cropSize = 320
    private let ciContext = CIContext()
    private var bgraBuffer: CVPixelBuffer?
    private var didAddObserver = false

    /// 弹出系统内容共享选择器（选"整个屏幕"即全屏采集）
    func start(ndiName: String, cropSize: Int) {
        self.cropSize = cropSize

        guard sender.start(withName: ndiName) else {
            DispatchQueue.main.async { self.lastError = "NDI 发送器创建失败" }
            return
        }

        let picker = SCContentSharingPicker.shared
        var pickerConfig = SCContentSharingPickerConfiguration()
        pickerConfig.showsMicrophoneControl = false
        picker.defaultConfiguration = pickerConfig
        if !didAddObserver {
            picker.add(self)
            didAddObserver = true
        }
        picker.present()
    }

    func stop() {
        if let s = stream {
            stream = nil
            Task { try? await s.stopCapture() }
        }
        if didAddObserver {
            SCContentSharingPicker.shared.remove(self)
            didAddObserver = false
        }
        sender.stop()
        DispatchQueue.main.async { self.isRunning = false }
    }

    deinit {
        if didAddObserver {
            SCContentSharingPicker.shared.remove(self)
        }
        sender.stop()
    }

    private func startStream(with filter: SCContentFilter) {
        // 停掉旧流
        if let old = stream {
            stream = nil
            Task { try? await old.stopCapture() }
        }

        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = max(2, Int(filter.contentRect.width * scale))
        config.height = max(2, Int(filter.contentRect.height * scale))
        // 注意：iOS 端 SCStreamConfiguration 仅开放 width/height；
        // 帧率/像素格式由系统决定（iPadOS 27 上限 60fps），非 BGRA 由 CoreImage 转换

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try newStream.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "sck.output", qos: .userInteractive)
            )
        } catch {
            DispatchQueue.main.async { self.lastError = "添加输出失败: \(error.localizedDescription)" }
            return
        }
        stream = newStream

        Task {
            do {
                try await newStream.startCapture()
                await MainActor.run {
                    self.isRunning = true
                    self.lastError = nil
                }
            } catch {
                await MainActor.run {
                    self.lastError = "采集启动失败: \(error.localizedDescription)"
                    self.isRunning = false
                }
            }
        }
    }

    // MARK: - 帧处理（BGRA 零拷贝 / YCbCr CoreImage 转换，中心裁剪 60fps）

    private func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let fullWidth = CVPixelBufferGetWidth(pixelBuffer)
        let fullHeight = CVPixelBufferGetHeight(pixelBuffer)
        let size = min(cropSize, min(fullWidth, fullHeight))
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)

        if format == kCVPixelFormatType_32BGRA {
            sendBGRAFromBuffer(pixelBuffer, size: size, fullWidth: fullWidth, fullHeight: fullHeight)
        } else {
            convertAndSend(pixelBuffer, size: size, fullWidth: fullWidth, fullHeight: fullHeight)
        }
    }

    private func sendBGRAFromBuffer(_ pixelBuffer: CVPixelBuffer, size: Int, fullWidth: Int, fullHeight: Int) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

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

    private func convertAndSend(_ pixelBuffer: CVPixelBuffer, size: Int, fullWidth: Int, fullHeight: Int) {
        prepareBGRABuffer(size: size)
        guard let dst = bgraBuffer else { return }

        let src = CIImage(cvPixelBuffer: pixelBuffer)
        let cropRect = CGRect(
            x: CGFloat(fullWidth - size) / 2,
            y: CGFloat(fullHeight - size) / 2,
            width: CGFloat(size),
            height: CGFloat(size)
        )
        let image = src
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

// MARK: - SCContentSharingPickerObserver

@available(iOS 27.0, *)
extension SCKCaptureManager: SCContentSharingPickerObserver {
    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didUpdateWith filter: SCContentFilter,
                              for stream: SCStream?) {
        startStream(with: filter)
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didCancelFor stream: SCStream?) {
        // 用户取消，不做处理
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async {
            self.lastError = "选择器错误: \(error.localizedDescription)"
        }
    }
}

// MARK: - SCStreamOutput / SCStreamDelegate

@available(iOS 27.0, *)
extension SCKCaptureManager: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen else { return }
        processVideoFrame(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.lastError = "采集中断: \(error.localizedDescription)"
            self.isRunning = false
        }
    }
}
