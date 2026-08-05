import XCTest
@testable import SecondBrainCore

/// **재완료(같은 회차에 완료를 두 번) — Stage 0 그물** (D-3 (a), 2026-08-05).
///
/// 이미 덮여 있는 것은 여기서 다시 안 짠다(중복 방지):
/// - 첫 압의 전진 4경우(온타임·이른·밀림·날짜만) = `RecurrenceCycleTests.testCompletionAdvance_*`
/// - lead 보존 = 같은 파일 `testCompletionAdvance_preservesLead`
/// - 비되풀이 → `status=done` 분기 = `RecurrenceCompletionTests.testCompletionChanges_nonRecurrence_setsDone`
/// - 완료 후 살아있음 / 취소 복원 = `RecurrenceCompletionTests` · `CompletionRoutingTests`
///
/// **안 덮여 있던 것 = 재완료.** 이 파일이 그 빈칸이다.
/// ⚠️ 아래 `_현재동작` 두 개는 **버그를 사실로 기록**한다 — 다음 커밋(가드 추가)에서 뒤집힌다.
/// 뒤집히는 diff 자체가 "고치기 전에 무엇이었나"의 기록이 된다.
final class RecurrenceRecompleteTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func d(_ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: day, hour: h, minute: min))!
    }
    private func rec(due: String, resurface: String? = nil, lastDone: String? = nil,
                     unit: String = "daily", paused: Bool = false) -> ResolvedItem {
        var f: [String: String] = ["type": "recurrence", "recur": unit, "due": due, "raw": "약"]
        if let resurface { f["resurface"] = resurface }
        if let lastDone { f[Recurrence.lastDoneKey] = lastDone }
        if paused { f[Recurrence.pausedKey] = "true" }
        return ResolvedItem(id: "a", fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }
    /// 완료 이벤트를 실제로 반영한 다음 상태 — "두 번 누르기"를 순수 함수로 재현한다.
    /// 빈 문자열은 값 지움(앱의 `set k=` 규약과 동일).
    private func apply(_ it: ResolvedItem, _ changes: [String: String]) -> ResolvedItem {
        var f = it.fields
        for (k, v) in changes { if v.isEmpty { f.removeValue(forKey: k) } else { f[k] = v } }
        return ResolvedItem(id: it.id, fields: f, deleted: it.deleted,
                            confirmed: it.confirmed, createdHLC: it.createdHLC)
    }
    private func press(_ it: ResolvedItem, at now: Date) -> (next: ResolvedItem, changes: [String: String]) {
        let c = Recurrence.completionChanges(for: it, now: now, calendar: utc)
        return (apply(it, c), c)
    }

    // MARK: 재완료 — 현재 동작(버그) 기록. 다음 커밋에서 뒤집힌다.

    /// **이른 완료 후 재압 = 하루를 건너뛴다.** 8시 약을 7시 30분에 먹고 누른 뒤 상세를 다시 열어
    /// 또 누르면(버튼이 `[이번 것 했어요]`로 돌아와 있다) **내일 약이 목록·알림에서 사라진다.**
    /// 이 설계의 출발점("약을 3일 놓친 것")이 바로 이 경우다.
    func testRecomplete_early_현재동작_두번전진() {
        let start = rec(due: "2026-08-05T08:00", resurface: "2026-08-05T07:00")
        let first = press(start, at: d(8, 5, 7, 30))
        XCTAssertEqual(first.changes["due"], "2026-08-06T08:00")
        let second = press(first.next, at: d(8, 5, 7, 35))
        XCTAssertEqual(second.changes["due"], "2026-08-07T08:00", "지금은 두 번째 압도 전진한다(버그)")
        XCTAssertEqual(second.changes["resurface"], "2026-08-07T07:00")
    }

    /// 늦은(정시) 완료 후 재압도 같다 — 이쪽은 `doneThisCycle`이 true라 화면엔 "완료됨"이 떠 있는데도 전진한다.
    func testRecomplete_late_현재동작_두번전진() {
        let start = rec(due: "2026-08-05T08:00")
        let first = press(start, at: d(8, 5, 9))
        XCTAssertEqual(first.changes["due"], "2026-08-06T08:00")
        XCTAssertTrue(Recurrence.doneThisCycle(first.next, now: d(8, 5, 9, 5), calendar: utc),
                      "늦은 완료 뒤엔 이번 회차가 닫혔다고 판정된다")
        let second = press(first.next, at: d(8, 5, 9, 5))
        XCTAssertEqual(second.changes["due"], "2026-08-07T08:00", "닫혔다고 판정되는데도 전진한다(버그)")
    }

    // MARK: 바뀌면 안 되는 것들(그물)

    /// 비되풀이는 **이미 멱등**하다 — 두 번 눌러도 `status=done`. 가드가 여기 닿으면 안 된다.
    func testNonRecurrence_alreadyIdempotent() {
        let t = ResolvedItem(id: "t", fields: ["type": "info-action", "due": "2026-08-05", "raw": "일"],
                             deleted: false, confirmed: false,
                             createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
        let first = press(t, at: d(8, 5, 9))
        XCTAssertEqual(first.changes, ["status": "done"])
        let second = press(first.next, at: d(8, 5, 9, 5))
        XCTAssertEqual(second.changes, ["status": "done"], "비되풀이 완료는 두 번 눌러도 같은 결과")
    }

    /// **다음 회차의 정당한 완료는 막히면 안 된다** — 이른 완료로 하루 넘어간 뒤, 다음 날 또 이르게 완료.
    /// (가드가 이걸 막으면 매일 약을 이르게 먹는 사람은 이틀에 한 번만 완료할 수 있게 된다.)
    func testNextCycle_earlyCompletion_mustStillWork() {
        let start = rec(due: "2026-08-05T08:00")
        let first = press(start, at: d(8, 5, 7, 30))          // → 08-06 08:00
        let nextDay = press(first.next, at: d(8, 6, 7, 30))   // 다음 날 이른 완료
        XCTAssertEqual(nextDay.changes["due"], "2026-08-07T08:00")
    }

    /// 다음 날 늦은 완료도 정당하다.
    func testNextCycle_lateCompletion_mustStillWork() {
        let start = rec(due: "2026-08-05T08:00")
        let first = press(start, at: d(8, 5, 9))              // → 08-06 08:00
        let nextDay = press(first.next, at: d(8, 6, 9))
        XCTAssertEqual(nextDay.changes["due"], "2026-08-07T08:00")
    }

    /// 놓친 항목(마감이 며칠 전)의 완료는 정당하다 — 놓친 날을 건너뛰고 다음 미래 회차로.
    func testMissedItem_completionMustStillWork() {
        let start = rec(due: "2026-08-02T08:00", lastDone: "2026-07-30T08:00")
        let c = press(start, at: d(8, 5, 14)).changes
        XCTAssertEqual(c["due"], "2026-08-06T08:00")
    }

    /// **취소 후 재완료가 열려 있어야 한다** — (b) 무를 수 없음을 남기더라도 취소 경로 자체는 막히지 않는다.
    /// 취소는 마감·미리 알림·lastDone을 직전 값으로 되돌린다 → 그 상태에서 완료가 다시 먹어야 한다.
    func testUndoThenRecomplete_pathStaysOpen() {
        let start = rec(due: "2026-08-05T08:00", resurface: "2026-08-05T07:00")
        let first = press(start, at: d(8, 5, 7, 30))
        // 취소 = 직전 값 복원(lastDone 제거 + 마감·미리 알림 되돌림)
        let undone = apply(first.next, ["due": "2026-08-05T08:00", "resurface": "2026-08-05T07:00",
                                       Recurrence.lastDoneKey: ""])
        XCTAssertNil(Recurrence.lastDone(undone, calendar: utc))
        let redo = press(undone, at: d(8, 5, 7, 40))
        XCTAssertEqual(redo.changes["due"], "2026-08-06T08:00", "취소 뒤엔 완료가 다시 먹어야 한다")
    }

    /// 꺼둔 항목도 **수동 완료는 먹는다**(현재 동작 고정) — 꺼두기는 자동 전진·알림·게시만 멈춘다.
    /// E-6 기준선에서 "바꾸는 것은 수동 편집과 완료뿐"이라고 적은 근거가 이것이다.
    func testDormant_manualCompletionStillApplies() {
        let off = rec(due: "2026-08-05T08:00", paused: true)
        let c = press(off, at: d(8, 5, 9)).changes
        XCTAssertEqual(c["due"], "2026-08-06T08:00")
        XCTAssertNotNil(c[Recurrence.lastDoneKey])
    }

    /// 앵커(마감)가 없으면 전진할 게 없다 — lastDone만 기록(현재 동작).
    func testNoAnchor_onlyLastDone() {
        var f: [String: String] = ["type": "recurrence", "recur": "daily", "raw": "약"]
        f["resurface"] = "2026-08-05T07:00"
        let it = ResolvedItem(id: "a", fields: f, deleted: false, confirmed: false,
                              createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
        let c = press(it, at: d(8, 5, 9)).changes
        XCTAssertNotNil(c[Recurrence.lastDoneKey])
        XCTAssertNil(c["due"])
    }
}
