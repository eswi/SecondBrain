import XCTest
@testable import SecondBrainCore

/// Stage 3 (양력 반복) — **완료 분기**(유일한 파괴적 지점)를 고정한다.
/// 되풀이 완료 = 마지막 완료 시점만 기록(status 무변경 → 항목 살아있음).
/// 비되풀이 완료 = status=done(보관함행, Stage 0 net과 동일).
final class RecurrenceCompletionTests: XCTestCase {

    private func h(_ w: Int64, _ c: Int, _ d: String) -> HLC { HLC(wallMillis: w, counter: c, deviceId: d) }
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func today(_ h: Int = 8) -> Date { utc.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: h))! }

    private func item(type: String?, lastDone: String? = nil, due: String? = nil,
                      recur: String? = nil, auto: String? = nil) -> ResolvedItem {
        var f: [String: String] = ["raw": "x"]
        if let type { f["type"] = type }
        if let lastDone { f["lastDone"] = lastDone }
        if let due { f["due"] = due }
        if let recur { f["recur"] = recur }
        if let auto { f["recurAuto"] = auto }
        return ResolvedItem(id: "a", fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }

    /// 라우팅 미러(정본 = InboxModel:193-198).
    private func route(_ r: MergeResult) -> (live: [ResolvedItem], done: [ResolvedItem]) {
        let active = r.live.filter { $0.type != "discard" }
        return (active.filter { $0.status != "done" }, active.filter { $0.status == "done" })
    }

    // ★ 분기: 되풀이 완료는 lastDone만, status 안 건드림.
    func testCompletionChanges_recurrence_writesLastDoneOnly() {
        let c = Recurrence.completionChanges(for: item(type: "recurrence"), now: today(), calendar: utc)
        XCTAssertEqual(c[Recurrence.lastDoneKey], ItemSchedule.dayTimeString(today(), calendar: utc))
        XCTAssertNil(c["status"], "되풀이 완료는 status를 건드리지 않는다")
    }

    // ★ 분기: 비되풀이 완료는 status=done(보관함행).
    func testCompletionChanges_nonRecurrence_setsDone() {
        let c = Recurrence.completionChanges(for: item(type: "info-action"), now: today(), calendar: utc)
        XCTAssertEqual(c["status"], "done")
        XCTAssertNil(c[Recurrence.lastDoneKey])
    }

    // ★ 되풀이 완료 후에도 살아있는 목록에 남는다(안 사라짐).
    func testRecurrenceCompleted_staysLive() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "약", extra: ["type": "recurrence"]),
            .edit(id: "a", hlc: h(2, 0, "i"), [Recurrence.lastDoneKey: "2026-08-02T08:00"]),
        ])
        let p = route(r)
        XCTAssertTrue(p.live.contains { $0.id == "a" }, "되풀이 완료는 살아있어야")
        XCTAssertFalse(p.done.contains { $0.id == "a" }, "보관함으로 가면 안 된다")
    }

    // "이번 회차 했나" — 게이트와 같은 마감 앵커 기준. 세 상태(했다/아직/넘어갔다)를 가른다.
    // now = 2026-08-02 12:00. 옛 doneToday(날짜기준)를 대체 — #4 모순(칩·게이트 갈림) 회귀 방지.
    func testDoneThisCycle() {
        // 했다: 마감 미래(전진됨) + lastDone ≥ 직전 회차(08-02). ← 실제 완료
        XCTAssertTrue(Recurrence.doneThisCycle(
            item(type: "recurrence", lastDone: "2026-08-02T08:00", due: "2026-08-03T08:00", recur: "daily"), now: today(12), calendar: utc))
        // 아직: 마감이 오늘·과거(게이트가 목록에 띄움) → 완료 아님
        XCTAssertFalse(Recurrence.doneThisCycle(
            item(type: "recurrence", lastDone: "2026-08-02T08:00", due: "2026-08-02T08:00", recur: "daily"), now: today(12), calendar: utc))
        // ★ 넘어갔다: 마감은 미래로 갔지만 lastDone은 직전 회차 전(자동완성 catch-up 전진) → "완료" 아님(거짓말 안 함)
        XCTAssertFalse(Recurrence.doneThisCycle(
            item(type: "recurrence", lastDone: "2026-08-01T08:00", due: "2026-08-03T08:00", recur: "daily", auto: "endOfDay"), now: today(12), calendar: utc))
        // 완료 기록 자체가 없음 → 넘어감
        XCTAssertFalse(Recurrence.doneThisCycle(
            item(type: "recurrence", due: "2026-08-03T08:00", recur: "daily"), now: today(12), calendar: utc))
        // 매주도 같은 기준으로 성립(직전 회차 = 마감 − 7일). 옛 "매주·매년은 Stage 4" 구멍이 앵커 기준으로 닫힘.
        XCTAssertTrue(Recurrence.doneThisCycle(
            item(type: "recurrence", lastDone: "2026-08-02T08:00", due: "2026-08-09T08:00", recur: "weekly"), now: today(12), calendar: utc))
        XCTAssertFalse(Recurrence.doneThisCycle(   // 매주 넘어감(전전 주 완료뿐)
            item(type: "recurrence", lastDone: "2026-07-26T08:00", due: "2026-08-09T08:00", recur: "weekly"), now: today(12), calendar: utc))
        // 앵커(마감) 없으면 "이번 회차" 정의 불가 → false
        XCTAssertFalse(Recurrence.doneThisCycle(
            item(type: "recurrence", lastDone: "2026-08-02T08:00", recur: "daily"), now: today(12), calendar: utc))
    }

    // 완료 취소 = 직전 완료 시점(streak 보존).
    func testPriorLastDone() {
        let events: [Event] = [
            .edit(id: "a", hlc: h(1, 0, "i"), [Recurrence.lastDoneKey: "2026-08-01T08:00"]),
            .edit(id: "a", hlc: h(2, 0, "i"), [Recurrence.lastDoneKey: "2026-08-02T08:00"]),   // 방금 것
        ]
        XCTAssertEqual(Recurrence.priorLastDone(in: events, id: "a"), "2026-08-01T08:00")   // 어제 것 보존
        // 완료가 한 번뿐이면 되돌릴 직전이 없다 → nil(비움)
        XCTAssertNil(Recurrence.priorLastDone(in: [events[1]], id: "a"))
    }
}
