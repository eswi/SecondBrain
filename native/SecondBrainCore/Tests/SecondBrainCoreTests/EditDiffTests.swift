import XCTest
@testable import SecondBrainCore

/// 상세 화면 draft 커밋(EditDiff)의 정확성 (edit-policy.md §2).
/// 특히 사용자 확인 요청: **수정 ≠ 확정** — 어떤 편집도 confirmed를 만들지 않는다.
final class EditDiffTests: XCTestCase {

    /// 편의 생성기: 필드로 ResolvedItem 구성.
    private func item(type: String? = nil, due: String? = nil, resurface: String? = nil) -> ResolvedItem {
        var f: [String: String] = ["raw": "x", "date": "2026-07-15", "time": "10:00", "source": "voice"]
        if let t = type { f["type"] = t }
        if let d = due { f["due"] = d }
        if let r = resurface { f["resurface"] = r }
        return ResolvedItem(id: "a", fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 0, counter: 0, deviceId: "legacy"))
    }

    // 1) 아무것도 안 고치면 변경 없음 → 이벤트 안 만듦
    func testNoChange_emptyDiff() {
        let it = item(type: "info", due: "2026-08-01", resurface: nil)
        let c = EditDiff.changes(type: "info", due: "2026-08-01", resurface: nil, from: it)
        XCTAssertTrue(c.isEmpty, "동일 값이면 커밋할 변경 없음")
    }

    // 2) [정책 핵심] 어떤 변경도 confirmed를 포함하지 않는다 (수정 ≠ 확정)
    func testNeverIncludesConfirmed() {
        let it = item(type: "info")
        let c = EditDiff.changes(type: "promise", due: "2026-08-01", resurface: "2026-07-20", from: it)
        XCTAssertNil(c["confirmed"], "EditDiff는 절대 confirmed를 커밋하지 않는다 — 확정은 별도 경로")
    }

    // 3) 여러 필드 동시 변경 → 한 dict(= 한 이벤트 = 한 묶음)
    func testMultiFieldChange() {
        let it = item(type: "info", due: nil, resurface: nil)
        let c = EditDiff.changes(type: "idea", due: "2026-08-01", resurface: "2026-07-20", from: it)
        XCTAssertEqual(c["type"], "idea")
        XCTAssertEqual(c["due"], "2026-08-01")
        XCTAssertEqual(c["resurface"], "2026-07-20")
        XCTAssertEqual(c.count, 3)
    }

    // 4) 원래 없던 시점을 안 건드리면 none이 안 써진다 (잡음 방지: nil == "" == "none")
    func testAbsentTimepoint_noNoise() {
        let it = item(type: "info", due: nil, resurface: nil)
        // draft가 nil / "" / "none" 어느 쪽이어도 "원래 없음"과 동일 → 변경 없음
        XCTAssertTrue(EditDiff.changes(type: "info", due: nil, resurface: nil, from: it).isEmpty)
        XCTAssertTrue(EditDiff.changes(type: "info", due: "", resurface: "", from: it).isEmpty)
        XCTAssertTrue(EditDiff.changes(type: "info", due: "none", resurface: "none", from: it).isEmpty)
    }

    // 5) 실제 날짜 지우기 → "none" 명시 기록 (§4-2 지우기)
    func testClearDate_writesNone() {
        let it = item(type: "info", due: "2026-08-01", resurface: "2026-07-20")
        let c = EditDiff.changes(type: "info", due: "none", resurface: "", from: it)
        XCTAssertEqual(c["due"], "none", "값 있던 due를 비우면 none 명시")
        XCTAssertEqual(c["resurface"], "none", "빈 문자열로 지워도 none으로 커밋")
    }

    // 6) 미분류로 되돌리기 → type="" (기존 set type= 경로와 동일)
    func testUnclassify_writesEmpty() {
        let it = item(type: "info")
        let c = EditDiff.changes(type: "", due: nil, resurface: nil, from: it)
        XCTAssertEqual(c["type"], "", "미분류 = 빈 문자열")
    }

    // 7) 미분류(nil)에서 안 고치면 변경 없음
    func testUnclassified_noChange() {
        let it = item(type: nil)
        XCTAssertTrue(EditDiff.changes(type: nil, due: nil, resurface: nil, from: it).isEmpty)
        XCTAssertTrue(EditDiff.changes(type: "", due: nil, resurface: nil, from: it).isEmpty, "nil==\"\" 미분류 동일")
    }

    // 8) resurface "weekly" 유지 → 변경 없음 / weekly 지우기 → none
    func testWeekly() {
        let it = item(type: "info", resurface: "weekly")
        XCTAssertTrue(EditDiff.changes(type: "info", due: nil, resurface: "weekly", from: it).isEmpty)
        let cleared = EditDiff.changes(type: "info", due: nil, resurface: "none", from: it)
        XCTAssertEqual(cleared["resurface"], "none", "weekly를 비우면 none")
    }
}
