import XCTest
@testable import SecondBrainCore

/// Stage 2 (양력 반복) — 반복 세부 필드가 **새 필드로 저장·병합**됨을 고정한다.
/// 필드별 LWW라 코드 추가 없이 병합되고, 기존 칸(due/resurface/status)과 독립.
final class RecurrenceConfigTests: XCTestCase {

    private func h(_ w: Int64, _ c: Int, _ d: String) -> HLC { HLC(wallMillis: w, counter: c, deviceId: d) }

    func testRecurrenceFields_roundTrip() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "2026-08-02", time: "t", source: "voice", raw: "약", extra: ["type": "recurrence"]),
            .edit(id: "a", hlc: h(2, 0, "i"), ["recur": "daily", "recurAuto": "endOfDay", "recurPaused": "true"]),
        ])
        let it = r.item("a")!
        XCTAssertEqual(Recurrence.unit(it), .daily)
        XCTAssertEqual(Recurrence.autoComplete(it), .endOfDay)
        XCTAssertTrue(Recurrence.isPaused(it))
    }

    func testRecurrence_defaults_whenUnset() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x", extra: ["type": "recurrence"]),
        ])
        let it = r.item("a")!
        XCTAssertNil(Recurrence.unit(it))
        XCTAssertEqual(Recurrence.autoComplete(it), .none)   // 기본 없음
        XCTAssertFalse(Recurrence.isPaused(it))
    }

    func testRecurrence_LWW_laterWins() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x", extra: ["type": "recurrence"]),
            .edit(id: "a", hlc: h(2, 0, "i"), ["recur": "daily"]),
            .edit(id: "a", hlc: h(3, 0, "i"), ["recur": "weekly"]),   // 더 큰 HLC
        ])
        XCTAssertEqual(Recurrence.unit(r.item("a")!), .weekly)
    }

    // 반복 필드는 기존 칸과 독립 — due/resurface/status를 안 건드린다.
    func testRecurrence_independentOfExistingFields() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x",
                    extra: ["type": "recurrence", "due": "2026-08-05", "resurface": "2026-08-03", "status": "open"]),
            .edit(id: "a", hlc: h(2, 0, "i"), ["recur": "daily", "recurPaused": "true"]),
        ])
        let it = r.item("a")!
        XCTAssertEqual(it.due, "2026-08-05")        // 그대로
        XCTAssertEqual(it.resurface, "2026-08-03")  // 그대로
        XCTAssertEqual(it.status, "open")           // 그대로
        XCTAssertEqual(Recurrence.unit(it), .daily)
        XCTAssertTrue(Recurrence.isPaused(it))
    }
}
