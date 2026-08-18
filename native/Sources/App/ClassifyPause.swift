import Foundation

/// **자동 분류 일시 중지** (2026-08-18 사용자 결정).
///
/// 자동 분류는 **재개발 예정**이다. 그래서 **기능을 지우지 않고 호출만 막는다** —
/// `InboxModel.classifyUnclassified`·`ClaudeClassifier`·`ClassifyPrompt`는 그대로 살아 있다.
///
/// **막은 자리 둘 (앱 안의 진입점 전부):**
/// - `InboxView` — 당겨서 분류(pull-to-classify). `.refreshable`이 이 안내를 띄운다.
/// - `SettingsView` — 「지금 분류하기」 버튼.
///
/// ⚠️ **앱 밖에 세 번째 경로가 있다 — `classify.py`.** `automation/setup-mac.sh`가 launchd
/// LaunchAgent(`com.secondbrain.classify`)로 **매시간 :00**에 돌리고, **`inbox.md`를 직접 덮어쓴다**
/// (op 로그가 아니다). **이 안내로는 못 막는다** — 기기마다 `automation/uninstall-mac.sh`를 돌려야 한다.
/// 2026-08-18 회사 맥북 차단 완료 · 집 맥미니는 사용자가 확인·차단.
///
/// **왜 멈췄나:** 자동 분류가 붙인 값이 **항목 필드에 그대로 써져** 미확정 항목이 분류·시점을 가진 채
/// 화면에 섰다. 재개발의 원칙은 **「자동은 준비까지, 결정은 사용자가」** — 자동은 *제안*을 준비하고,
/// 사람이 수락할 때 필드에 쓰이면서 함께 확정된다. **미확정 항목의 필드는 비어 있는 것이 정상이다.**
/// (제안을 어디에 어떤 수명으로 둘지는 재개발 범위 — 여기서 정하지 않는다. `memory-philosophy.md` 참조.)
enum ClassifyPause {
    /// 화면에 나오는 말 — **사용자가 정했다**(2026-08-18). 바꾸려면 사용자에게 묻는다.
    static let title = "이 기능은 일시 중지되었습니다"
}
