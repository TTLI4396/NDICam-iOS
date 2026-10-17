import SwiftUI

/// iPadOS 27+ 系统采集区块（ScreenCaptureKit，退后台持续）
@available(iOS 27.0, *)
struct SCKSection: View {
    @StateObject private var sck = SCKCaptureManager()
    let ndiName: String
    let cropSize: Int

    var body: some View {
        Text("系统采集（推荐 · iPadOS 27 · 退后台持续）")
            .font(.caption.bold())
            .foregroundColor(Color(red: 0.35, green: 0.95, blue: 0.6))
            .frame(maxWidth: .infinity, alignment: .leading)

        Button {
            if sck.isRunning {
                sck.stop()
            } else {
                sck.start(ndiName: ndiName.isEmpty ? "NDICam iOS" : ndiName,
                          cropSize: cropSize)
            }
        } label: {
            Label(sck.isRunning ? "停止系统采集" : "开始系统采集（退后台不断流）",
                  systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(sck.isRunning
                              ? Color(red: 0.85, green: 0.25, blue: 0.3)
                              : Color(red: 0.1, green: 0.75, blue: 0.4))
                )
        }

        if let error = sck.lastError {
            Text(error)
                .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                .font(.caption)
        }

        Text("ScreenCaptureKit 系统采集：点击后系统选择器选\"整个屏幕\"\n退后台/切 App 持续发送中心裁剪 · 60fps")
            .font(.caption2)
            .foregroundColor(Color(red: 0.55, green: 0.8, blue: 0.65))
            .multilineTextAlignment(.center)

        Divider().background(Color.white.opacity(0.25))
    }
}

struct SenderView: View {
    @StateObject private var screen = ScreenManager(ndiName: "NDICam iOS")
    @State private var ndiName = "NDICam iOS"
    @State private var cropSize = 320

    private let cropSizes = [256, 320, 416]

    var body: some View {
        ZStack {
            // 深蓝黑渐变背景
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.07, blue: 0.14),
                         Color(red: 0.02, green: 0.03, blue: 0.08)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

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
                    } else {
                        Label("待 机", systemImage: "moon.zzz")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.35))
                            .foregroundColor(Color(red: 0.65, green: 0.75, blue: 0.9))
                            .cornerRadius(8)
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                // 中心裁剪区域示意
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(red: 0.3, green: 0.7, blue: 1.0).opacity(0.5), lineWidth: 1.5)
                        .frame(width: 220, height: 220)
                    Rectangle()
                        .stroke(Color(red: 0.2, green: 0.95, blue: 0.55), lineWidth: 2.5)
                        .frame(width: CGFloat(cropSize) / 416.0 * 220,
                               height: CGFloat(cropSize) / 416.0 * 220)
                    Text("\(cropSize)×\(cropSize)")
                        .font(.system(.callout, design: .monospaced).bold())
                        .foregroundColor(Color(red: 0.2, green: 0.95, blue: 0.55))
                        .offset(y: 122)
                }

                Text(screen.isRunning
                     ? "正在发送屏幕中心 \(cropSize)×\(cropSize) 区域"
                     : "NDI 发送已停止")
                    .font(.subheadline)
                    .foregroundColor(screen.isRunning
                        ? Color(red: 0.35, green: 0.9, blue: 1.0)   // 运行中：青色
                        : Color(red: 1.0, green: 0.75, blue: 0.35)) // 停止：橙色

                Spacer()

                VStack(spacing: 12) {
                    if let error = screen.lastError {
                        Text(error)
                            .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                            .font(.caption)
                    }

                    // ── 系统采集（iPadOS 27+，后台持续）──
                    if #available(iOS 27.0, *) {
                        SCKSection(ndiName: ndiName, cropSize: cropSize)
                    }

                    // ── 前台模式 ──
                    Text("前台模式（退后台约 30 秒后停止）")
                        .font(.caption.bold())
                        .foregroundColor(Color(red: 0.45, green: 0.7, blue: 1.0))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("裁剪尺寸", selection: $cropSize) {
                        ForEach(cropSizes, id: \.self) { size in
                            Text("\(size)").tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(screen.isRunning)

                    HStack {
                        Text("源名称")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.6, green: 0.8, blue: 1.0))
                        TextField("NDI 源名称", text: $ndiName)
                            .textFieldStyle(.roundedBorder)
                            .disabled(screen.isRunning)
                    }

                    Button(screen.isRunning ? "停止发送" : "开始发送（前台）") {
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
                    .tint(screen.isRunning ? Color(red: 0.85, green: 0.25, blue: 0.3)
                                           : Color(red: 0.2, green: 0.5, blue: 0.95))
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("NDI 屏幕发送")
        .navigationBarTitleDisplayMode(.inline)
    }
}
