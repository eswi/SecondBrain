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
///
/// ### 정정 (2026-08-05 저녁, (b) Stage 2)
/// 이 파일은 (a)의 **`stepBack` 휴리스틱 2절**을 전제로 짜였는데, **그 2절에 구멍이 있었다** —
/// `now ≤ 직전 회차` 조건이 **회차 시각을 지나면 풀려** 재압이 마감을 또 밀었다(구멍 1).
/// 가드는 삭제됐고 이제 **가드 = 표시 = `doneThisCycle`** 하나다. 아래 네 테스트를 정정한다:
/// - `testRecomplete_early_isIdempotent` — under-claim 단정이 뒤집힘(이른 완료도 "완료"로 보인다)
/// - `testBothClausesAreNeeded` → `testOnePredicate_guardEqualsDisplay` (전제 자체가 사라짐)
/// - `testNextCycle_earlyCompletion_*` · `testWeekly_recompleteIsIdempotent` — **회차가 열려야**
///   다음 이른 완료가 가능하다(승인된 대가). 지우지 않고 무엇이 바뀌었는지 남긴다.
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
    /// **정정(Stage 2):** 옛 단정은 *"이른 완료라 under-claim — `doneThisCycle`이 false"* 였다.
    /// **그 under-claim이 (b)의 뿌리였고 이번에 없앴다** → 이제 true다(화면에 "이번 회차 완료됨"이 뜬다).
    /// 그리고 재압 멱등은 **회차 시각 뒤에도** 유지된다(옛 2절은 거기서 풀렸다 — 구멍 1).
    func testRecomplete_early_isIdempotent() {
        let start = rec(due: "2026-08-05T08:00", resurface: "2026-08-05T07:00")
        let first = press(start, at: d(8, 5, 7, 30))
        XCTAssertEqual(first.changes["due"], "2026-08-06T08:00")
        XCTAssertTrue(Recurrence.doneThisCycle(first.next, now: d(8, 5, 7, 35), calendar: utc),
                      "이른 완료도 '했다'로 보인다 — under-claim 해소")
        let second = press(first.next, at: d(8, 5, 7, 35))
        XCTAssertTrue(second.changes.isEmpty, "재압은 빈 변경이어야 한다")
        // 상태가 그대로다 = 멱등. 세 번 눌러도 같다.
        XCTAssertEqual(second.next.due, "2026-08-06T08:00")
        XCTAssertEqual(second.next.resurface, "2026-08-06T07:00")
        XCTAssertTrue(press(second.next, at: d(8, 5, 7, 40)).changes.isEmpty)
        // ★ 구멍 1이 닫혔다 — 회차 시각(08:00)을 지나도, 하루 종일 지나도 멱등이다.
        for t in [d(8, 5, 8, 1), d(8, 5, 9), d(8, 5, 23)] {
            XCTAssertTrue(press(second.next, at: t).changes.isEmpty, "회차 시각 뒤에도 막혀야 한다")
        }
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

    /// **정정(Stage 2) — 옛 이름은 `testBothClausesAreNeeded`였다.**
    /// 옛 전제: 표시(`doneThisCycle`)와 가드(`alreadyClosedThisCycle`)가 **다른 판정**이고, 가드엔
    /// 이른 완료를 잡는 2절이 따로 필요하다. **그 2절이 구멍 1의 원인이었고**(회차 시각 뒤에 풀림),
    /// 옛 테스트는 그 구조를 정상으로 못박고 있었다(5-A의 교훈이 여기서 반복됐다).
    ///
    /// 지금은 **가드 = 표시**다. 그 등식이 dead button을 구조적으로 없앤다:
    /// 판정이 false여서 버튼이 보이는 상태에서 누르면 **반드시** 변경이 나온다(빈 변경이 아니다).
    func testOnePredicate_guardEqualsDisplay() {
        let cases: [(String, ResolvedItem, Date)] = [
            ("이른 완료 직후",   press(rec(due: "2026-08-05T08:00"), at: d(8, 5, 7, 30)).next, d(8, 5, 7, 35)),
            ("이른 완료+회차 뒤", press(rec(due: "2026-08-05T08:00"), at: d(8, 5, 7, 30)).next, d(8, 5, 9)),
            ("정시 완료 직후",   press(rec(due: "2026-08-05T08:00"), at: d(8, 5, 9)).next,     d(8, 5, 9, 5)),
            ("완료 전(첫 압)",   rec(due: "2026-08-05T08:00"),                                  d(8, 5, 9)),
            ("옛 항목(필드 없음)", rec(due: "2026-08-10T08:00", lastDone: "2026-08-01T08:00"),  d(8, 5, 9)),
        ]
        for (name, it, now) in cases {
            let shown = Recurrence.doneThisCycle(it, now: now, calendar: utc)
            let blocked = Recurrence.completionChanges(for: it, now: now, calendar: utc).isEmpty
            XCTAssertEqual(shown, blocked, "\(name): 표시와 가드가 갈리면 그 자리가 dead button이다")
        }
    }

    /// **마감을 손으로 먼 미래로 옮긴 항목의 이른 완료는 막히지 않는다.**
    /// 옛 항목(완료 증인 없음)이라 폴백 경로 — 값이 지금과 같아야 한다.
    func testFarFutureDue_earlyCompletionNotBlocked() {
        let it = rec(due: "2026-08-10T08:00", lastDone: "2026-08-01T08:00")
        XCTAssertNil(it.fields[Recurrence.lastDoneDueKey], "전제: 옛 항목")
        XCTAssertFalse(Recurrence.doneThisCycle(it, now: d(8, 5, 9), calendar: utc))
        XCTAssertEqual(press(it, at: d(8, 5, 9)).changes["due"], "2026-08-11T08:00")
    }

    /// **정정(Stage 2).** 옛 단정: 이른 완료 뒤 **다음 주의 이른 완료(이틀 전)도 통과**한다.
    /// 이제 막힌다 — 승인된 대가다. 구멍 1(회차 시각 뒤의 재압이 회차를 먹음)을 닫으면 피할 수 없다:
    /// **"잘못된 재압"과 "다음 회차의 이른 완료"는 필드 상태가 완전히 같고 `now`만 다르다.**
    /// 둘을 가르려면 "다음 회차가 언제 열리나"가 필요하고, 그 값은 **미리 알림(게시 시작)** 이다.
    /// 유실이 아니라 기다림이다 — 회차가 열리면 목록에 떠서 재촉한다.
    func testWeekly_recompleteIsIdempotent() {
        let start = rec(due: "2026-08-05T08:00", unit: "weekly")
        let first = press(start, at: d(8, 3, 10))          // 이른 완료(이틀 전)
        XCTAssertEqual(first.changes["due"], "2026-08-12T08:00")
        XCTAssertTrue(press(first.next, at: d(8, 3, 10, 5)).changes.isEmpty)
        XCTAssertTrue(press(first.next, at: d(8, 10, 10)).changes.isEmpty,
                      "미리 알림이 없으면 회차(08-12 08:00)가 열리기 전엔 다시 못 누른다")
        XCTAssertEqual(press(first.next, at: d(8, 12, 9)).changes["due"], "2026-08-19T08:00",
                       "회차가 열리면 정상 통과")
    }

    /// ★ **위 대가의 반대편 — 미리 알림을 걸면 그 시각부터 열린다.**
    /// "이르게 하려면 미리 알림을 걸어라"는 미리 알림 칸의 **원래 뜻**(§3-A: 미리 알림 = 게시 시작)과 같다.
    func testLeadOpensTheNextCycleEarly() {
        let start = rec(due: "2026-08-05T08:00", resurface: "2026-08-05T07:00")
        let first = press(start, at: d(8, 5, 7, 30)).next          // → 마감 08-06 08:00 · lead 08-06 07:00
        XCTAssertTrue(press(first, at: d(8, 6, 6, 30)).changes.isEmpty, "lead 전엔 아직 안 열렸다")
        XCTAssertEqual(press(first, at: d(8, 6, 7)).changes["due"], "2026-08-07T08:00",
                       "lead 시각부터 다음 회차의 이른 완료가 열린다")
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
        XCTAssertFalse(Recurrence.doneThisCycle(fresh, now: d(8, 3, 9), calendar: utc),
                       "완료 이력이 없으면 첫 압이다 — 회차 시각 전이어도 막으면 안 된다")
        let c = press(fresh, at: d(8, 3, 9)).changes
        XCTAssertEqual(c["due"], "2026-08-06T08:00")
        XCTAssertEqual(c["resurface"], "2026-08-06T07:00", "lead 보존")
        XCTAssertNotNil(c[Recurrence.lastDoneKey])
    }

    /// **정정(Stage 2).** 옛 단정: 미리 알림 없는 항목도 **다음 날 07:30(마감 전)에 이르게 완료**된다.
    /// 옛 주석의 우려 *"막히면 이틀에 한 번만 완료할 수 있게 된다"* 는 **실현되지 않는다** — 매일 되고,
    /// 다만 **회차가 열린 뒤**(미리 알림 없으면 마감 시각)여야 한다. 30분 기다림이지 유실이 아니다.
    /// 이르게 하는 습관이 있으면 미리 알림을 걸면 된다(`testLeadOpensTheNextCycleEarly`).
    func testNextCycle_earlyCompletion_opensWhenTheCycleOpens() {
        let start = rec(due: "2026-08-05T08:00")               // 미리 알림 없음 → 마감 시각이 곧 게시 시작
        let first = press(start, at: d(8, 5, 7, 30))           // → 08-06 08:00
        XCTAssertTrue(press(first.next, at: d(8, 6, 7, 30)).changes.isEmpty, "아직 회차가 안 열렸다")
        XCTAssertEqual(press(first.next, at: d(8, 6, 8)).changes["due"], "2026-08-07T08:00",
                       "회차 시각이 되면 열린다(정각 포함)")
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
        // 취소 = 직전 값 복원. **`lastDoneDue`도 함께 지운다** — `InboxModel.undoRecurComplete`와 같은 규약
        // (안 지우면 마감만 과거로 가고 증인은 미래를 가리켜 등식이 어긋난 채 남는다).
        let undone = apply(first.next, ["due": "2026-08-05T08:00", "resurface": "2026-08-05T07:00",
                                       Recurrence.lastDoneKey: "", Recurrence.lastDoneDueKey: ""])
        XCTAssertNil(Recurrence.lastDone(undone, calendar: utc))
        XCTAssertNil(Recurrence.lastDoneDue(undone, calendar: utc))
        XCTAssertFalse(Recurrence.doneThisCycle(undone, now: d(8, 5, 7, 40), calendar: utc),
                       "취소하면 '완료' 표시가 사라져 취소 버튼도 함께 사라진다 — 이력을 거슬러 못 올라간다")
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
