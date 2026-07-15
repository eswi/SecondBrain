import XCTest
@testable import SecondBrainCore

final class FragmentParserTests: XCTestCase {

    func testParsesHeaderAndClassifiedFields() {
        let sample = """
        - 2026-07-15 10:51 | voice | 우유 사오기
          type: info-action
          due: none
          resurface: weekly
          status: open
          ? 언제 어디서 살 건가요?
        - 2026-07-15 11:00 | web | https://example.com — 왜: 참고
        """
        let items = FragmentParser.parse(sample, sourceFile: "inbox-iphone.md")
        XCTAssertEqual(items.count, 2)

        XCTAssertEqual(items[0].source, "voice")
        XCTAssertEqual(items[0].raw, "우유 사오기")
        XCTAssertEqual(items[0].type, "info-action")
        XCTAssertEqual(items[0].due, "none")
        XCTAssertEqual(items[0].resurface, "weekly")
        XCTAssertEqual(items[0].status, "open")
        XCTAssertEqual(items[0].question, "언제 어디서 살 건가요?")
        XCTAssertEqual(items[0].sourceFile, "inbox-iphone.md")

        // 미분류 항목 — 필드 없음
        XCTAssertEqual(items[1].source, "web")
        XCTAssertNil(items[1].type)
        XCTAssertNil(items[1].question)
    }

    func testIgnoresNonItemLinesAndBlankSeparators() {
        let sample = """
        # 이 제목 줄은 무시된다

        - 2026-07-15 09:00 | voice | 첫 항목

        - 2026-07-15 09:05 | voice | 둘째 항목
        """
        let items = FragmentParser.parse(sample)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].raw, "첫 항목")
        XCTAssertEqual(items[1].raw, "둘째 항목")
    }

    func testStableIdFromHeader() {
        let a = FragmentParser.parse("- 2026-07-15 09:00 | voice | 같은 원문")[0]
        let b = FragmentParser.parse("- 2026-07-15 09:00 | voice | 같은 원문\n  type: idea")[0]
        // 분류 필드가 붙어도 id는 헤더 기반이라 동일(합치기 중복제거용)
        XCTAssertEqual(a.id, b.id)
    }
}
