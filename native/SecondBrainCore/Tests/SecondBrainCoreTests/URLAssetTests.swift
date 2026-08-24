import XCTest
@testable import SecondBrainCore

/// URL 자료의 순수 계산 — 「URL인가」와 「네모에 보일 짧은 이름」.
///
/// ⚠️ **이 묶음은 「결정 파수꾼」이 아니다** — 보통 시험이다(구현이 맞나를 본다).
/// 단, **짧은 이름 표는 2026-08-24에 잰 폭에서 나왔다**(§3-Z-4) — 규칙을 바꾸면
/// **62pt에 안 들어가는 이름이 다시 생긴다.** 그때는 `CLAUDE.md` 계측 규칙 5의 도구로 **다시 재라.**
final class URLAssetTests: XCTestCase {

    func testShortName() {
        let cases: [(String, String?)] = [
            ("https://example.com/a/b",        "example"),
            ("https://www.youtube.com",        "youtube"),
            ("https://ko.wikipedia.org/wiki/x","wikipedia"),
            ("https://brunch.co.kr/@x",        "brunch"),
            ("https://news.v.daum.net/v/1",    "daum"),
            ("https://namu.wiki/w/x",          "namu"),
            // 실데이터 둘 (inbox*.md · 2026-08-24)
            ("https://wowanalytica.com",       "wowanalytica"),
            ("https://questionablyepic.com",   "questionablyepic"),
            // 스킴 없이 붙여넣는 흔한 꼴
            ("example.com",                    "example"),
            ("그냥 글자",                       nil),
        ]
        for (input, want) in cases {
            XCTAssertEqual(URLAsset.shortName(input), want, "입력=\(input)")
        }
    }

    func testIsLikelyURL() {
        // ✅ 통과해야 하는 것 — 느슨하게 본다(사내망·포트·한글 경로·사용자 스킴)
        for s in ["https://example.com", "http://10.0.0.5:8080/x", "example.com",
                  "https://ko.wikipedia.org/wiki/이차_기억", "myapp://open/x",
                  "https://example.com/a b", "http://localhost:3000"] {
            XCTAssertTrue(URLAsset.isLikelyURL(s), "막지 말아야 한다: \(s)")
        }
        // ⛔ 막아야 하는 것
        for s in ["", "   ", "그냥 적어둔 메모", "여러 줄\nhttps://example.com"] {
            XCTAssertFalse(URLAsset.isLikelyURL(s), "막아야 한다: \(s)")
        }
    }

    func testNormalizedAddsSchemeButKeepsValueOtherwise() {
        XCTAssertEqual(URLAsset.normalized("example.com/a?b=1"), "https://example.com/a?b=1")
        // 스킴이 있으면 **손대지 않는다** — 퍼센트 인코딩을 다시 하지 않는다
        XCTAssertEqual(URLAsset.normalized("https://example.com/%20?q=1"), "https://example.com/%20?q=1")
        XCTAssertEqual(URLAsset.normalized("  https://example.com/x  "), "https://example.com/x")
    }
}
