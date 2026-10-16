import SwiftUI
import AVFoundation

/// 摄像头预览层
struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        previewLayer.frame = UIScreen.main.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            previewLayer.frame = uiView.bounds
        }
    }
}

struct SenderView: View {
    @StateObject private var camera = CameraManager(ndiName: "NDICam iOS")
    @State private var ndiName = "NDICam iOS"

    var body: some View {
        ZStack {
            if camera.isRunning {
                CameraPreviewView(previewLayer: camera.previewLayer)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "video.badge.waveform")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.6))
                    Text("NDI 发送已停止")
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            VStack {
                HStack {
                    if camera.isRunning {
                        Label("ON AIR", systemImage: "dot.radiowaves.left.and.right")
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                VStack(spacing: 12) {
                    if let error = camera.lastError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    TextField("NDI 源名称", text: $ndiName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(camera.isRunning)

                    Button(camera.isRunning ? "停止发送" : "开始发送") {
                        if camera.isRunning {
                            camera.stop()
                        } else {
                            camera.start(ndiName: ndiName.isEmpty ? "NDICam iOS" : ndiName)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(camera.isRunning ? .red : .blue)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("NDI 发送")
        .navigationBarTitleDisplayMode(.inline)
    }
}
