import Foundation

/// STT(음성 받아쓰기) 로컬 설정 — @AppStorage/UserDefaults. 데이터 아님(PrincipleSettings와 동일 패턴).
/// 플랫폼 비의존(단순 키/기본값) — SettingsView(cross-platform)와 SpeechCapture(iOS)가 함께 읽는다.
enum SpeechSettings {
    static let autoStopKey = "sttAutoStopSeconds"
    static let defaultAutoStop = 7        // 마지막 말 끝난 뒤 이만큼 침묵이면 자동 [완료]
    static let maxAutoStop = 30
    static let minAutoStop = 0            // 0 = 자동 종료 끄기([완료] 버튼으로만 종료)

    /// 현재 자동 종료 대기(초). 키가 없으면 기본 7 — `integer(forKey:)`의 0 기본값을
    /// "끄기"로 오인하지 않도록 존재 여부를 먼저 본다.
    static var autoStopSeconds: Int {
        UserDefaults.standard.object(forKey: autoStopKey) == nil
            ? defaultAutoStop
            : UserDefaults.standard.integer(forKey: autoStopKey)
    }
}
