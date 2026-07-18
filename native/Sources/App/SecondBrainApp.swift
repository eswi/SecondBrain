import SwiftUI

/// 네이티브 v1 앱 진입점 (iOS·macOS 공유). 루트 = 탭바(RootView).
@main
struct SecondBrainApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
