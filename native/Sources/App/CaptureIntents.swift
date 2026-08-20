#if os(iOS)
import AppIntents

/// 액션 버튼·단축어 → 앱을 열고 바로 음성 수집(STT)을 시작한다.
/// **메인 앱 타깃에 정의** — 별도 App Extension 불필요, 특수 entitlement 없음(무료 서명 OK).
struct CaptureMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "새 기억 음성으로 수집"
    static let description = IntentDescription("SecondBrain을 열고 바로 음성 받아쓰기를 시작합니다.")
    static let openAppWhenRun = true   // 마이크 UI가 필요하므로 앱을 연다

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureLauncher.shared.requestCapture()
        return .result()
    }
}

/// 앱 단축어 등록 — Shortcuts 앱·액션 버튼 설정에 자동 노출(별도 등록 절차 불필요).
struct SecondBrainShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureMemoryIntent(),
            phrases: [
                // **앱 이름 하나짜리 구절**(2026-08-20 사용자). ⚠️ **된다고 확인된 것이 아니다** —
                // Apple 문서·WWDC 예시는 전부 동사가 붙은 꼴(`"Open \(.applicationName)"`)이고
                // **토큰 하나짜리 예시가 없다.** Siri가 이것을 「앱을 열어라」로 해석할 수 있다.
                // **그래서 아래 셋을 안 지웠다** — 짧은 것이 안 먹어도 긴 것이 살아 있다.
                // 판정은 실기기에서 사용자가 한다(빌드는 문법만 본다).
                "\(.applicationName)",
                "\(.applicationName)으로 기억하기",
                "\(.applicationName) 음성 수집",
                "\(.applicationName)에 기억 남기기",
            ],
            shortTitle: "음성으로 새 기억",
            systemImageName: "mic.fill"
        )
    }
}
#endif
