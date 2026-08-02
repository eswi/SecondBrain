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

    private func item(type: String?, lastDone: String? = nil) -> ResolvedItem {
        var f: [String: String] = ["raw": "x"]
        if let type { f["type"] = type }
        if let lastDone { f["lastDone"] = lastDone }
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

    // "오늘 했나" (최소판) — 오늘 완료면 true.
    func testDoneToday() {
        XCTAssertTrue(Recurrence.doneToday(item(type: "recurrence", lastDone: "2026-08-02T08:00"), now: today(12), calendar: utc))
        XCTAssertFalse(Recurrence.doneToday(item(type: "recurrence", lastDone: "2026-08-01T08:00"), now: today(12), calendar: utc))
        XCTAssertFalse(Recurrence.doneToday(item(type: "recurrence"), now: today(12), calendar: utc))   // 완료 없음
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
