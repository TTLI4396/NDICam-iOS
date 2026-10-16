import AVFoundation
import UIKit

/// 摄像头采集 + NDI 发送
final class CameraManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var lastError: String?

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.ndicam.session")
    private let outputQueue = DispatchQueue(label: "com.ndicam.output", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()

    private let sender = NDISenderBridge()
    private(set) var ndiName: String
    private var frameCount: UInt64 = 0

    init(ndiName: String) {
        self.ndiName = ndiName
        super.init()
    }

    func start(ndiName: String) {
        self.ndiName = ndiName
        start()
    }

    /// 用于预览的 layer
    var previewLayer: AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else {
                DispatchQueue.main.async { self.lastError = "无摄像头权限" }
                return
            }
            self.sessionQueue.async { self.configureAndStart() }
        }
    }

    private func configureAndStart() {
        guard !session.isRunning else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            DispatchQueue.main.async { self.lastError = "无法打开摄像头" }
            return
        }
        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(videoOutput) else {
            DispatchQueue.main.async { self.lastError = "无法添加视频输出" }
            return
        }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        guard sender.start(withName: ndiName) else {
            DispatchQueue.main.async { self.lastError = "NDI 发送器创建失败" }
            return
        }

        session.startRunning()
        DispatchQueue.main.async {
            self.isRunning = true
            self.lastError = nil
        }
    }

    func stop() {
        sessionQueue.async {
            self.session.stopRunning()
            self.sender.stop()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    deinit {
        sender.stop()
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int32(CVPixelBufferGetHeight(pixelBuffer))
        let bytesPerRow = Int32(CVPixelBufferGetBytesPerRow(pixelBuffer))

        sender.sendVideoFrameBGRA(
            baseAddress.assumingMemoryBound(to: UInt8.self),
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            frameRateN: 30,
            frameRateD: 1
        )
        frameCount &+= 1
    }
}
