import XCTest
@testable import SecondBrainCore

/// 상세 화면 draft 커밋(EditDiff)의 정확성 (edit-policy.md §2).
/// 특히 사용자 확인 요청: **수정 ≠ 확정** — 어떤 편집도 confirmed를 만들지 않는다.
///
/// ★ **이것은 「결정을 지키는 시험」이다**(`CLAUDE.md` 「시험을 쓰는 법」).
/// ⚠️ **깨진다면 [저장]과 [기억하기]의 분리가 무너진 것**일 수 있다 — `edit-policy.md` §2를 먼저 본다.
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

    // 9) raw 미제공(nil) = 하위호환 — 본문을 diff에 안 담는다.
    func testRaw_omittedByDefault() {
        let it = item(type: "info")
        let c = EditDiff.changes(type: "info", due: nil, resurface: nil, from: it)
        XCTAssertNil(c["raw"], "raw 인자 없으면 diff에 raw 없음")
    }

    // 10) raw 안 고치면 변경 없음 / 고치면 글자 그대로.
    func testRaw_changeExact() {
        let it = item()   // item.raw == "x"
        XCTAssertTrue(EditDiff.changes(type: nil, due: nil, resurface: nil, raw: "x", from: it).isEmpty,
                      "같은 본문이면 변경 없음")
        let c = EditDiff.changes(type: nil, due: nil, resurface: nil, raw: "고친 본문", from: it)
        XCTAssertEqual(c["raw"], "고친 본문")
        XCTAssertEqual(c.count, 1, "본문만 바꾸면 raw 한 필드")
    }

    // 11) [결정 3] 앞뒤 공백은 trim하지 않고 그대로 보존 — 앱이 사람 글을 조용히 바꾸지 않는다.
    func testRaw_preservesEdgeWhitespace() {
        let it = item()   // "x"
        let c = EditDiff.changes(type: nil, due: nil, resurface: nil, raw: "  앞뒤 공백  ", from: it)
        XCTAssertEqual(c["raw"], "  앞뒤 공백  ", "앞뒤 공백 그대로 커밋")
    }

    // 12) 본문+분류 동시 수정 → 한 dict(한 이벤트). raw는 성역 아님, 함께 커밋된다.
    func testRaw_withTypeChange() {
        let it = item(type: "idea")
        let c = EditDiff.changes(type: "info", due: nil, resurface: nil, raw: "정정본", from: it)
        XCTAssertEqual(c["type"], "info")
        XCTAssertEqual(c["raw"], "정정본")
        XCTAssertEqual(c.count, 2)
    }

    // 13) [로드 시 dirty 아님 — 원문 항상 편집 가능 방식의 핵심 가드]
    // "열고 → 안 만지고 → 나가기"가 팝업 없이 통과해야 한다. draft raw = item.raw ?? "" (DetailView.init과 동일)일 때
    // nil·앞뒤 공백·줄바꿈·특수문자 항목도 로드만으로 변경이 생기면 안 된다.
    func testRaw_loadNeverDirty_edgeItems() {
        let raws: [String?] = [nil, "", "  앞뒤 공백  ", "첫 줄\n둘째 줄", "a|b", "이모지 🙂"]
        for r in raws {
            var f: [String: String] = ["date": "d", "time": "t", "source": "voice"]
            if let r { f["raw"] = r }
            let it = ResolvedItem(id: "a", fields: f, deleted: false, confirmed: false,
                                  createdHLC: HLC(wallMillis: 0, counter: 0, deviceId: "legacy"))
            let draftRaw = it.raw ?? ""   // DetailView: _raw = State(initialValue: item.raw ?? "")
            let c = EditDiff.changes(type: it.type, due: it.due, resurface: it.resurface,
                                     raw: draftRaw, from: it)
            XCTAssertTrue(c.isEmpty, "로드만으로 dirty면 안 됨(원문=\(String(describing: r))): \(c)")
        }
    }
}
