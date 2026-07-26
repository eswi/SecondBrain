import SwiftUI

/// 네이티브 v1 앱 진입점 (iOS·macOS 공유). 루트 = 탭바(RootView).
@main
struct SecondBrainApp: App {
    init() {
        // 일회성 정리: 제거된 '분류 관리 → 재설계 후보'(§7 — 분류는 코드 고정)의 UserDefaults 키만 지운다.
        // 후보 아이디어는 classification-redesign-open-questions.md로 이관·보존됨(2026-07-26).
        // 이 키만 대상 — sb_folder_bookmark·sb_hlc_last 등 핵심 키는 절대 안 건드린다.
        UserDefaults.standard.removeObject(forKey: "reclass.candidates.v1")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
