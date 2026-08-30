import XCTest
@testable import SecondBrainCore

/// **결정을 지키는 시험** — 「새 녹음은 빈 줄 둘로 갈라 붙는다」(2026-08-30 사용자 결정).
///
/// ① **무슨 결정인가:** 수집 화면에서 [정지] 뒤 다시 녹음해 텍스트가 더해질 때,
///    기존 텍스트 끝에 **엔터 두 번**을 넣고 이어 붙인다. 한 번의 말 안의 조각 회전은 **빈칸 하나** 그대로다.
///    (정본 = `TranscriptJoin` 머리주석의 표 · 계기 = *"기록을 다시 해야 함"* 버그와 같은 지시)
/// ② **사실:** 이음새가 둘이라 상수도 둘이고, 빈 쪽에는 이음새를 넣지 않는다.
/// ③ **깨지면 무엇을 의심하나:** 구현이 아니라 **누군가 두 이음새를 하나로 합친 것**을 의심한다.
///    합치는 방향 둘 다 사용자가 반려한 것이다(달라붙거나 · 조각마다 끊긴다).
final class TranscriptJoinTests: XCTestCase {

    func testParagraphIsTwoNewlines() {
        XCTAssertEqual(TranscriptJoin.paragraph, "\n\n")
    }

    func testSegmentIsSingleSpace() {
        XCTAssertEqual(TranscriptJoin.segment, " ")
    }

    /// 새 녹음 — 앞 말과 **빈 줄 둘**로 갈린다.
    func testNewTakeJoinsWithBlankLine() {
        let joined = TranscriptJoin.join("아침에 약 먹기", "그리고 우산도 챙기자",
                                        with: TranscriptJoin.paragraph)
        XCTAssertEqual(joined, "아침에 약 먹기\n\n그리고 우산도 챙기자")
    }

    /// 조각 회전 — 같은 말이므로 **빈칸 하나**다. ⛔ 이 둘이 같아지면 결정이 깨진 것이다.
    func testSegmentRotationJoinsWithSpace() {
        let joined = TranscriptJoin.join("아침에 약", "먹기", with: TranscriptJoin.segment)
        XCTAssertEqual(joined, "아침에 약 먹기")
        XCTAssertNotEqual(joined, "아침에 약\n\n먹기")
    }

    /// 앞이 비면 이음새를 안 넣는다 — 편집칸에 빈 줄이 먼저 보이면 사용자가 지우려 든다.
    func testEmptyBaseGetsNoSeparator() {
        XCTAssertEqual(TranscriptJoin.join("", "첫 말", with: TranscriptJoin.paragraph), "첫 말")
    }

    /// 뒤가 비면 이음새를 안 넣는다 — 재개했다가 아무 말도 안 하고 멈춘 경우.
    func testEmptyAdditionGetsNoSeparator() {
        XCTAssertEqual(TranscriptJoin.join("앞의 말", "", with: TranscriptJoin.paragraph), "앞의 말")
    }

    /// 여러 번 이어 붙여도 앞의 빈 줄이 보존된다(세 번째 녹음).
    func testThirdTakeKeepsEarlierBreaks() {
        var s = TranscriptJoin.join("하나", "둘", with: TranscriptJoin.paragraph)
        s = TranscriptJoin.join(s, "셋", with: TranscriptJoin.paragraph)
        XCTAssertEqual(s, "하나\n\n둘\n\n셋")
    }
}
