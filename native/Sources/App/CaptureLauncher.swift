import SwiftUI

/// 앱 밖(액션 버튼·단축어)에서 "수집 시트를 열어라"를 앱에 전달하는 공유 신호.
/// App Intent가 `requestCapture()`를 부르면 RootView가 관찰해 CaptureSheet를 띄운다.
@MainActor
final class CaptureLauncher: ObservableObject {
    static let shared = CaptureLauncher()
    private init() {}

    @Published var showCapture = false

    func requestCapture() { showCapture = true }
}
