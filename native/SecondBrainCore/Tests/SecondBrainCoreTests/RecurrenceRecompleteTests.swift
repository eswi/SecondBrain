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

    // MARK: 재완료 멱등 (D-3 (a) — 가드 추가 후)
    //
    // **정정(2026-08-05).** 두 테스트는 처음 `_현재동작_두번전진`으로 짜서 **버그를 사실로 기록**했다.
    // 옛 기대: 마감 08-05 → 1차 08-06 → **2차 08-07**(하루 건너뜀). 가드 추가로 2차가 **빈 변경**이 된다.

    /// **이른 완료 후 재압 = 아무 일도 없다.** 옛 동작은 하루를 건너뛰었다 — 8시 약을 7시 30분에 먹고
    /// 누른 뒤 상세를 다시 열어 또 누르면(버튼이 `[이번 것 했어요]`로 돌아와 있다) **내일 약이 목록·알림에서
    /// 사라졌다.** 이 설계의 출발점("약을 3일 놓친 것")이 바로 그 경우라 고쳐야 했다.
    /// 이른 완료는 `doneThisCycle`이 못 잡는다(under-claim) → 2절("방금 닫은 회차 시각 전")이 잡는다.
    func testRecomplete_early_isIdempotent() {
        let start = rec(due: "2026-08-05T08:00", resurface: "2026-08-05T07:00")
        let first = press(start, at: d(8, 5, 7, 30))
        XCTAssertEqual(first.changes["due"], "2026-08-06T08:00")
        XCTAssertFalse(Recurrence.doneThisCycle(first.next, now: d(8, 5, 7, 35), calendar: utc),
                       "이른 완료라 under-claim — 1절로는 안 잡힌다(2절이 필요한 이유)")
        let second = press(first.next, at: d(8, 5, 7, 35))
        XCTAssertTrue(second.changes.isEmpty, "재압은 빈 변경이어야 한다")
        // 상태가 그대로다 = 멱등. 세 번 눌러도 같다.
        XCTAssertEqual(second.next.due, "2026-08-06T08:00")
        XCTAssertEqual(second.next.resurface, "2026-08-06T07:00")
        XCTAssertTrue(press(second.next, at: d(8, 5, 7, 40)).changes.isEmpty)
    }

    /// 늦은(정시) 완료 후 재압 — 이쪽은 `doneThisCycle`이 true라 1절이 잡는다.
    func testRecomplete_late_isIdempotent() {
        let start = rec(due: "2026-08-05T08:00")
        let first = press(start, at: d(8, 5, 9))
        XCTAssertEqual(first.changes["due"], "2026-08-06T08:00")
        XCTAssertTrue(Recurrence.doneThisCycle(first.next, now: d(8, 5, 9, 5), calendar: utc))
        XCTAssertTrue(press(first.next, at: d(8, 5, 9, 5)).changes.isEmpty)
        XCTAssertEqual(first.next.due, "2026-08-06T08:00")
    }

    /// 두 절이 **각각** 필요하다 — 어느 하나만으로는 두 경우를 다 못 막는다(위 둘의 근거를 직접 고정).
    func testBothClausesAreNeeded() {
        // 이른 완료 후: 1절 false, 그래도 닫힘 판정은 true(2절 덕).
        let early = press(rec(due: "2026-08-05T08:00"), at: d(8, 5, 7, 30)).next
        XCTAssertFalse(Recurrence.doneThisCycle(early, now: d(8, 5, 7, 35), calendar: utc))
        XCTAssertTrue(Recurrence.alreadyClosedThisCycle(early, now: d(8, 5, 7, 35), calendar: utc))
        // 늦은 완료 후: 1절 true. 2절 조건(now ≤ 직전 회차)은 이미 지나서 false다.
        let late = press(rec(due: "2026-08-05T08:00"), at: d(8, 5, 9)).next
        XCTAssertTrue(Recurrence.doneThisCycle(late, now: d(8, 5, 9, 5), calendar: utc))
        XCTAssertTrue(Recurrence.alreadyClosedThisCycle(late, now: d(8, 5, 9, 5), calendar: utc))
    }

    /// **마감을 손으로 먼 미래로 옮긴 항목의 이른 완료는 막히지 않는다** — 2절의 "직전 완료가 방금 닫은
    /// 회차의 창 안" 조건이 이걸 지킨다. 이 조건이 없으면 5일 앞 마감을 완료할 수 없게 된다.
    func testFarFutureDue_earlyCompletionNotBlocked() {
        let it = rec(due: "2026-08-10T08:00", lastDone: "2026-08-01T08:00")
        XCTAssertFalse(Recurrence.alreadyClosedThisCycle(it, now: d(8, 5, 9), calendar: utc))
        XCTAssertEqual(press(it, at: d(8, 5, 9)).changes["due"], "2026-08-11T08:00")
    }

    /// 매주·매년도 같은 판정 — `stepBack`이 주기를 따르므로 창이 한 주기다.
    func testWeekly_recompleteIsIdempotent() {
        let start = rec(due: "2026-08-05T08:00", unit: "weekly")
        let first = press(start, at: d(8, 3, 10))          // 이른 완료(이틀 전)
        XCTAssertEqual(first.changes["due"], "2026-08-12T08:00")
        XCTAssertTrue(press(first.next, at: d(8, 3, 10, 5)).changes.isEmpty)
        // 다음 주 이른 완료는 정당 — 통과해야 한다.
        XCTAssertEqual(press(first.next, at: d(8, 10, 10)).changes["due"], "2026-08-19T08:00")
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

    /// **첫 완료는 이력이 없으므로 절대 안 막힌다** — 2절의 `lastDone` 있음 조건이 지키는 자리.
    ///
    /// 다른 테스트의 첫 압은 전부 `now > 방금 닫은 회차`라 3번째 조건에서 이미 탈락한다 →
    /// **이 절이 단독으로 시험되는 유일한 경우**가 여기다: 새로 만든 항목을 **한 주기보다 더 이르게** 완료.
    /// (마감 08-05, 08-03에 누름 → 닫은 회차 08-04, `now ≤ 08-04`라 3번째 조건이 참이 된다.)
    func testFirstCompletion_noHistory_neverBlocked() {
        let fresh = rec(due: "2026-08-05T08:00", resurface: "2026-08-05T07:00")
        XCTAssertNil(Recurrence.lastDone(fresh, calendar: utc), "이력 없음이 이 테스트의 전제")
        XCTAssertFalse(Recurrence.alreadyClosedThisCycle(fresh, now: d(8, 3, 9), calendar: utc),
                       "완료 이력이 없으면 첫 압이다 — 회차 시각 전이어도 막으면 안 된다")
        let c = press(fresh, at: d(8, 3, 9)).changes
        XCTAssertEqual(c["due"], "2026-08-06T08:00")
        XCTAssertEqual(c["resurface"], "2026-08-06T07:00", "lead 보존")
        XCTAssertNotNil(c[Recurrence.lastDoneKey])
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
