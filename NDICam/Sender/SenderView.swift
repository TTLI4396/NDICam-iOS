import SwiftUI
import ReplayKit

/// 系统直播选择器（Broadcast Upload Extension 入口）
struct BroadcastPicker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        DispatchQueue.main.async {
            RPBroadcastActivityViewController.load { broadcastVC, _ in
                guard let broadcastVC = broadcastVC else { return }
                vc.present(broadcastVC, animated: true)
            }
        }
        return vc
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct SenderView: View {
    @StateObject private var screen = ScreenManager(ndiName: "NDICam iOS")
    @State private var ndiName = "NDICam iOS"
    @State private var cropSize = 320
    @State private var showBroadcastPicker = false

    private let cropSizes = [256, 320, 416]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    if screen.isRunning {
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

                // 中心裁剪区域示意
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        .frame(width: 220, height: 220)
                    Rectangle()
                        .stroke(Color.green, lineWidth: 2)
                        .frame(width: CGFloat(cropSize) / 416.0 * 220,
                               height: CGFloat(cropSize) / 416.0 * 220)
                    Text("\(cropSize)×\(cropSize)")
                        .font(.caption)
                        .foregroundColor(.green)
                        .offset(y: 120)
                }

                Text(screen.isRunning
                     ? "正在发送屏幕中心 \(cropSize)×\(cropSize) 区域"
                     : "NDI 发送已停止")
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                VStack(spacing: 12) {
                    if let error = screen.lastError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    Button {
                        showBroadcastPicker = true
                    } label: {
                        Label("开始直播（后台持续发送）", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Text("直播模式：退后台/切 App 仍持续发送整屏中心 320×320，60fps")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Divider()

                    Picker("裁剪尺寸", selection: $cropSize) {
                        ForEach(cropSizes, id: \.self) { size in
                            Text("\(size)×\(size)").tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(screen.isRunning)

                    TextField("NDI 源名称", text: $ndiName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(screen.isRunning)

                    Button(screen.isRunning ? "停止发送" : "开始发送") {
                        if screen.isRunning {
                            screen.stop()
                        } else {
                            screen.start(
                                ndiName: ndiName.isEmpty ? "NDICam iOS" : ndiName,
                                cropSize: cropSize
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(screen.isRunning ? .red : .blue)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("NDI 屏幕发送")
        .navigationBarTitleDisplayMode(.inline)
        .background(
            Group {
                if showBroadcastPicker {
                    BroadcastPicker()
                        .frame(width: 0, height: 0)
                        .onAppear { showBroadcastPicker = false }
                }
            }
        )
    }
}
