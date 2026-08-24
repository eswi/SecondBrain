import Foundation

/// **URL 자료의 순수 계산** — 「이것이 URL인가」와 「네모에 보일 이름」.
///
/// ⚠️ **왜 Core에 있나:** 화면에 쓰이는 값이지만 **순수 계산이라 시험으로 못 박을 수 있다.**
/// 이 저장소가 줄 나누기를 `SecondBrainCore`로 옮긴 것과 같은 이유다.
///
/// 결정: `docs/native/media-expansion-design.md` **§3-Z-2**(일곱) · 문구는 **§3-Z-6**.
public enum URLAsset {

    // MARK: 이것이 URL인가 — 「URL이 아닌 것 같아요」를 띄우는 판정

    /// **저장을 막을지 정하는 판정**(사용자 결정 2026-08-24: *"「URL이 아닌 것 같아요」 한 줄 + 저장을 말린다"*).
    ///
    /// **느슨하게 본다** — 사내망 주소·포트·한글 경로·사용자 지정 스킴을 다 통과시킨다.
    /// ⛔ **엄하게 볼 수 없다:** 이 앱은 사용자가 적은 것을 **버리지 않는 쪽**이고,
    /// 여기서 막힌 것은 **사용자가 다시 손댈 길이 없다**(시트가 저장을 안 해준다).
    ///
    /// 요구는 셋뿐이다: ① 스킴이 있다(`x://`) ② 호스트가 있다 ③ 공백만은 아니다.
    /// **스킴이 없으면 `https://`를 붙여 본다** — 사람이 `example.com`만 붙여넣는 일이 흔하다.
    public static func isLikelyURL(_ raw: String) -> Bool {
        normalized(raw) != nil
    }

    /// 저장할 꼴로 다듬는다 — 앞뒤 공백을 떼고, **스킴이 없으면 `https://`를 붙인다.**
    /// URL로 볼 수 없으면 nil.
    ///
    /// ⚠️ **값은 사용자가 준 그대로에 가깝게 둔다** — 퍼센트 인코딩을 다시 하지 않는다.
    /// 왕복은 쟀다(§3-Z-3): 한글·공백·`|`·2000자까지 무손실로 저장된다.
    public static func normalized(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // 줄바꿈이 든 것은 URL 하나가 아니다(붙여넣기 사고)
        guard !s.contains(where: { $0 == "\n" || $0 == "\r" }) else { return nil }

        if let u = URL(string: s), let scheme = u.scheme, !scheme.isEmpty {
            guard u.host?.isEmpty == false else { return nil }
            return s
        }
        // 스킴이 없다 — `https://`를 붙여 본다
        let guessed = "https://" + s
        guard let u = URL(string: guessed), u.host?.isEmpty == false else { return nil }
        // 점이 하나도 없으면 호스트로 보기 어렵다(「그냥 글」과 가른다). `localhost`는 예외로 통과.
        let host = u.host ?? ""
        guard host.contains(".") || host == "localhost" else { return nil }
        return guessed
    }

    // MARK: 네모에 보일 이름 — 62pt에 들어가는 것

    /// **62pt 네모에 넣을 짧은 이름.** 도메인 전체는 **못 들어간다**(2026-08-24 쟀다 · §3-Z-4:
    /// 가장 짧은 `brunch.co.kr`도 11pt에서 **66.3pt**인데 네모 안쪽은 **54.6pt**다).
    /// 그래서 **끝(`.com`)을 뗀 이름**을 쓴다 — 쟀다: `daum` 29.1 · `youtube` 42.6 · `wikipedia` 49.1pt.
    ///
    /// **규칙(문서화한 어림짐작):** `www.`를 떼고 → 마지막 조각이 **두 글자면 끝 둘**(`co.kr`),
    /// **아니면 끝 하나**(`com`·`net`·`wiki`)를 버린다 → 남은 것의 **마지막 조각**.
    ///
    /// | 넣은 것 | 나오는 것 |
    /// |---|---|
    /// | `example.com` · `www.youtube.com` | `example` · `youtube` |
    /// | `ko.wikipedia.org` | `wikipedia` |
    /// | `brunch.co.kr` | `brunch` |
    /// | `news.v.daum.net` | `daum` |
    /// | `namu.wiki` | `namu` |
    ///
    /// ⚠️ **공개 접미사 목록(Public Suffix List)을 안 쓴다** — 그건 갱신되는 데이터가 필요하다.
    /// **그래서 예외가 있을 수 있다**(`foo.github.io` → `github`). ⛔ **그때 깨지는 것은 글자뿐이고
    /// 기능이 아니다** — 누르면 여전히 원래 URL이 열린다(「덮는 값」 · 계측 규칙 7).
    public static func shortName(_ raw: String) -> String? {
        guard let s = normalized(raw), let host = URL(string: s)?.host, !host.isEmpty else { return nil }
        var parts = host.lowercased().split(separator: ".").map(String.init)
        if parts.first == "www" { parts.removeFirst() }
        guard !parts.isEmpty else { return nil }
        if parts.count >= 2 {
            let drop = (parts.last?.count == 2) ? 2 : 1
            if parts.count > drop { parts.removeLast(drop) }
        }
        return parts.last ?? host
    }

    /// 뷰어·시트에 그대로 보일 호스트(`www.` 포함). 못 읽으면 nil.
    public static func host(_ raw: String) -> String? {
        guard let s = normalized(raw) else { return nil }
        return URL(string: s)?.host
    }
}
