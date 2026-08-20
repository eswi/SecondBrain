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
                // ✅ **앱 이름 하나면 된다 — 실기기에서 확인됐다**(2026-08-20 사용자):
                // *"SecondBrain만 말해도 수집 모드로 바로 들어가네."*
                // Siri가 **「앱을 열어라」로 새지 않고** 이 인텐트로 온다.
                //
                // ⚠️ **문서로는 알 수 없던 값이다** — Apple 문서·WWDC 예시는 전부 동사가 붙은 꼴
                // (`"Open \(.applicationName)"`)이고 **토큰 하나짜리 예시가 없다.**
                // 빌드는 문법까지만 본다(구절이 `Metadata.appintents`에 들어간 것은 확인했다).
                // **눌러야 알 수 있었고, 눌러서 알았다.**
                //
                // 긴 셋(「…으로 기억하기」·「… 음성 수집」·「…에 기억 남기기」)은 **안전망이었고
                // 짧은 것이 먹었으므로 걷어냈다**(사용자 결정 2026-08-20).
                "\(.applicationName)",
            ],
            shortTitle: "음성으로 새 기억",
            systemImageName: "mic.fill"
        )
    }
}
#endif
