import SwiftUI

@main
struct NDICamApp: App {
    init() {
        // 深色导航栏 + 浅色标题（iOS 15 兼容）
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.14, alpha: 1)
        nav.titleTextAttributes = [.foregroundColor: UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(red: 0.4, green: 0.75, blue: 1.0, alpha: 1)

        // 启动即主动请求系统录屏权限（iOS 26+）
        NDScreenPermission.requestScreenRecordingPermission()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationView {
                    SenderView()
                }
                .tabItem {
                    Label("发送", systemImage: "video.badge.waveform")
                }

                ReceiverView()
                    .tabItem {
                        Label("接收", systemImage: "play.rectangle.on.rectangle")
                    }
            }
        }
    }
}
