import Foundation

/// **받아쓰기를 이어 붙이는 자리** — 조각과 조각 사이에 무엇을 넣나.
///
/// ## 왜 Core에 있나 — 이음새가 둘이고, 둘을 합치면 조용히 틀린다
///
/// 수집 화면의 텍스트는 **두 군데서** 자란다. 화면에서는 똑같이 「글자가 늘어난 것」으로 보이는데
/// 사용자에게는 전혀 다른 일이다:
///
/// | 이음새 | 무엇 | 무엇으로 잇나 |
/// |---|---|---|
/// | **조각 회전** | 한 번의 말 안에서 인식기가 끊은 자리(침묵 1.2초 · `isFinal` · 온디바이스 ~1분 한계) | **빈칸 하나** — 사용자에게는 한 문장이다 |
/// | **새 녹음** | [정지] 뒤 다시 [녹음]을 눌러 **이어 말한 것** | **빈 줄 둘**(엔터 두 번 · 2026-08-30 사용자 결정) |
///
/// ⛔ **이 시험이 깨진다면 구현이 틀린 것이 아니라 누군가 두 이음새를 하나로 합친 것이다** —
/// 그때는 위 표를 다시 본다. **빈칸 하나로 합치면** 새 녹음이 앞 말에 달라붙어 어디서 다시 말했는지
/// 알 수 없고, **빈 줄 둘로 합치면** 한 문장이 조각마다 끊겨 읽을 수 없게 된다.
///
/// ⚠️ **여기까지가 「화면의 편집칸」 이야기다.** 저장되는 `raw`(성역 create 블록)는 **한 줄**이라
/// 줄바꿈을 담지 못한다(`EventWriter.serialize`의 `- date time | source | raw`) — 그 자리에서
/// `InboxModel.capture`가 빈 줄을 빈칸으로 접는다.
public enum TranscriptJoin {

    /// **새 녹음**을 이어 붙일 때의 이음새 — 엔터 두 번.
    public static let paragraph = "\n\n"

    /// **한 번의 말 안**에서 조각을 이을 때의 이음새.
    public static let segment = " "

    /// `base` 뒤에 `addition`을 붙인다.
    ///
    /// 어느 한쪽이 비면 **이음새를 넣지 않는다** — 넣으면 아직 아무 말도 안 했는데
    /// 편집칸에 빈 줄 둘이 먼저 보인다(그러면 사용자가 그것을 지우려 든다).
    public static func join(_ base: String, _ addition: String, with separator: String) -> String {
        if base.isEmpty { return addition }
        if addition.isEmpty { return base }
        return base + separator + addition
    }
}
