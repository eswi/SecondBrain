import XCTest
@testable import SecondBrainCore

/// **결정을 지키는 시험** — 「수집한 원문의 줄바꿈은 저장해도 살아 있다」(2026-08-31 사용자 결정).
///
/// ① **무슨 결정인가:** *"수집단에서 줄바꿈 처리한 것은 줄바꿈으로 계속 유지되어야 해."*
///    create 블록은 **한 줄**(`- <날짜> <시각> | <source> | <원문>`)이라 진짜 줄바꿈을 못 담는다 →
///    `RawLine`이 `\n`(두 글자)으로 접고 파서가 되돌린다. 정본 = `RawLine` 머리주석.
/// ② **사실:** 접기·되돌리기가 **왕복**하고, 옛 데이터(역슬래시 0개)에서는 **되돌리기가 항등**이다
///    → **레거시 id 해시가 안 바뀐다.**
/// ③ **깨지면 무엇을 의심하나:** 구현이 아니라 **누군가 원문을 다시 「한 줄로 접었다」**(빈칸 치환으로
///    되돌렸다)거나 **이스케이프 순서를 바꿨다**(역슬래시를 나중에 두 배로 만들면 `\n`이 망가진다)를 의심한다.
///    ⛔ `InboxModel.capture`에서 `replacingOccurrences(of: "\n", with: " ")`가 되살아나면 이 결정이 죽는다.
final class RawLineTests: XCTestCase {

    // MARK: 왕복

    func testRoundtripKeepsBlankLine() {
        let raw = "아침에 약 먹기\n\n그리고 우산도 챙기자"
        let line = RawLine.encode(raw)
        XCTAssertFalse(line.contains("\n"), "접힌 꼴에 진짜 줄바꿈이 남으면 create 블록이 쪼개진다")
        XCTAssertEqual(line, "아침에 약 먹기\\n\\n그리고 우산도 챙기자")
        XCTAssertEqual(RawLine.decode(line), raw)
    }

    func testRoundtripKeepsBackslash() {
        let raw = #"경로는 C:\새폴더 이고 줄바꿈은 \n 이라고 적었다"#
        XCTAssertEqual(RawLine.decode(RawLine.encode(raw)), raw)
    }

    /// ⛔ **순서가 뒤바뀌면 여기서 깨진다** — 역슬래시를 나중에 두 배로 만들면
    /// 방금 만든 `\n`의 역슬래시까지 두 배가 되어 되돌릴 때 글자 `\n`이 된다.
    func testBackslashBeforeNewlineOrder() {
        XCTAssertEqual(RawLine.encode("a\\\nb"), "a\\\\\\nb")
        XCTAssertEqual(RawLine.decode(RawLine.encode("a\\\nb")), "a\\\nb")
    }

    // MARK: 옛 데이터 — 되돌리기가 항등이어야 한다

    /// 역슬래시가 없는 옛 원문은 **한 글자도 안 바뀐다** → 레거시 id 해시가 안 밀린다.
    func testDecodeIsIdentityWithoutBackslash() {
        for raw in ["주차 위치", "아침 간염 약 먹기!", "대구. 서부신세계영상의학과 영업건 진행 건",
                    "URL은 https://a.b/c?d=e&f=g 이다", "숫자 129-86-31394"] {
            XCTAssertEqual(RawLine.decode(raw), raw)
        }
    }

    /// **모르는 이스케이프는 뜻을 지어내지 않는다**(관용적 파서 원칙).
    func testUnknownEscapeIsKept() {
        XCTAssertEqual(RawLine.decode(#"a\tb"#), #"a\tb"#)
        XCTAssertEqual(RawLine.decode(#"끝에 홀로 남은 \"#), #"끝에 홀로 남은 \"#)
    }

    // MARK: 직렬화 → 파싱 왕복 (진짜 자리)

    func testCreateEventRoundtripsThroughFile() {
        let raw = "첫 줄\n\n둘째 줄"
        let e = Event.create(id: "495BA146-2191-4495-9837-804FC427FAD3",
                             hlc: HLC(wallMillis: 1_787_000_000_000, counter: 0, deviceId: "iphone-4532"),
                             date: "2026-08-31", time: "01:20", source: "voice", raw: raw,
                             extra: ["device": "iPhone 16 Pro"])
        let text = EventWriter.serialize(e)
        // create 블록의 **첫 줄**에 진짜 줄바꿈이 있으면 그 뒤가 필드 줄로 읽혀 버린다.
        let first = text.components(separatedBy: "\n")[0]
        XCTAssertTrue(first.hasSuffix("첫 줄\\n\\n둘째 줄"), "접힌 꼴이 첫 줄에 있어야 한다: \(first)")

        let parsed = EventLog.parse(text)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.fields["raw"], raw, "되돌린 원문이 줄바꿈까지 같아야 한다")
        XCTAssertEqual(parsed.first?.fields["device"], "iPhone 16 Pro", "필드 줄이 안 밀려야 한다")
    }

    /// **새 녹음의 이음새가 저장을 통과한다** — `TranscriptJoin.paragraph`와 짝인 시험.
    func testParagraphJoinSurvivesStorage() {
        let raw = TranscriptJoin.join("먼저 말한 것", "이어 말한 것", with: TranscriptJoin.paragraph)
        let parsed = EventLog.parse(EventWriter.serialize(
            Event.create(id: "ID-1", hlc: HLC(wallMillis: 1, counter: 0, deviceId: "d"),
                         date: "2026-08-31", time: "01:20", source: "voice", raw: raw)))
        XCTAssertEqual(parsed.first?.fields["raw"], "먼저 말한 것\n\n이어 말한 것")
    }
}
