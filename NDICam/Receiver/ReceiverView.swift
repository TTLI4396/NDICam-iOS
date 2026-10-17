import SwiftUI

struct ReceiverView: View {
    @StateObject private var model = ReceiverModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 视频显示区域
                ZStack {
                    Color(red: 0.03, green: 0.04, blue: 0.09)
                    if let frame = model.currentFrame {
                        Image(uiImage: frame)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: model.connectedName != nil
                                  ? "antenna.radiowaves.left.and.right"
                                  : "tv.slash")
                                .font(.largeTitle)
                                .foregroundColor(Color(red: 0.35, green: 0.6, blue: 0.95))
                            Text(model.connectedName != nil ? "等待视频帧…" : "未连接")
                                .font(.subheadline)
                                .foregroundColor(model.connectedName != nil
                                    ? Color(red: 0.35, green: 0.9, blue: 1.0)   // 已连接等帧：青色
                                    : Color(red: 1.0, green: 0.75, blue: 0.35)) // 未连接：橙色
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

                if let connected = model.connectedName {
                    HStack {
                        Label(connected, systemImage: "checkmark.circle.fill")
                            .foregroundColor(Color(red: 0.25, green: 0.9, blue: 0.5))
                            .font(.subheadline.bold())
                        Spacer()
                        Button("断开", role: .destructive) { model.disconnect() }
                    }
                    .padding()
                    .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                }

                // 源列表
                List(model.sources, id: \.name) { source in
                    Button {
                        model.connect(to: source)
                    } label: {
                        HStack {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundColor(Color(red: 0.4, green: 0.75, blue: 1.0))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                    .font(.headline)
                                    .foregroundColor(Color(red: 0.55, green: 0.85, blue: 1.0))
                                Text(source.address)
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.6, green: 0.65, blue: 0.75))
                            }
                        }
                    }
                    .listRowBackground(Color(red: 0.06, green: 0.08, blue: 0.15))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(red: 0.03, green: 0.04, blue: 0.09))
            }
            .background(Color(red: 0.03, green: 0.04, blue: 0.09).ignoresSafeArea())
            .navigationTitle("NDI 接收")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(model.isScanning ? "停止扫描" : "扫描") {
                        model.isScanning ? model.stopScanning() : model.startScanning()
                    }
                    .foregroundColor(Color(red: 0.4, green: 0.75, blue: 1.0))
                }
            }
        }
        .onAppear { model.startScanning() }
        .onDisappear { model.stopScanning() }
    }
}
