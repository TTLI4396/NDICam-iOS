import SwiftUI

struct ReceiverView: View {
    @StateObject private var model = ReceiverModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 视频显示区域
                ZStack {
                    Color.black
                    if let frame = model.currentFrame {
                        Image(uiImage: frame)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Text(model.connectedName != nil ? "等待视频帧…" : "未连接")
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

                if let connected = model.connectedName {
                    HStack {
                        Label(connected, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Spacer()
                        Button("断开", role: .destructive) { model.disconnect() }
                    }
                    .padding()
                }

                // 源列表
                List(model.sources, id: \.name) { source in
                    Button {
                        model.connect(to: source)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                                .font(.headline)
                            Text(source.address)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("NDI 接收")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(model.isScanning ? "停止扫描" : "扫描") {
                        model.isScanning ? model.stopScanning() : model.startScanning()
                    }
                }
            }
        }
        .onAppear { model.startScanning() }
        .onDisappear { model.stopScanning() }
    }
}
