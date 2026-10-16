import SwiftUI

/// NDI 源浏览 + 接收
final class ReceiverModel: ObservableObject {
    @Published var sources: [NDISource] = []
    @Published var currentFrame: UIImage?
    @Published var connectedName: String?
    @Published var isScanning = false

    private let finder = NDIFinderBridge()
    private let receiver = NDIReceiverBridge()
    private var scanTimer: Timer?

    func startScanning() {
        guard finder.start() else { return }
        isScanning = true
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let found = self.finder.currentSources()
            DispatchQueue.main.async { self.sources = found }
        }
    }

    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
        finder.stop()
        isScanning = false
    }

    func connect(to source: NDISource) {
        receiver.onFrame = { [weak self] cgImage in
            let image = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                self?.currentFrame = image
            }
        }
        if receiver.connect(to: source) {
            DispatchQueue.main.async { self.connectedName = source.name }
        }
    }

    func disconnect() {
        receiver.disconnect()
        DispatchQueue.main.async {
            self.connectedName = nil
            self.currentFrame = nil
        }
    }

    deinit {
        scanTimer?.invalidate()
        receiver.disconnect()
        finder.stop()
    }
}
