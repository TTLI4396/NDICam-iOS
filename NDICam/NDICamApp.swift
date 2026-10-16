import SwiftUI

@main
struct NDICamApp: App {
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
