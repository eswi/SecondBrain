import SwiftUI

/// 네이티브 v1 앱 진입점 (iOS·macOS 공유). Phase 1 = 걷는 뼈대.
@main
struct SecondBrainApp: App {
    var body: some Scene {
        WindowGroup {
            InboxListView()
        }
    }
}
