import XCTest
@testable import SecondBrainCore

/// Stage 4 (양력 반복) — 회차 계산(순수 함수). **앵커 = 마감(due) = 회차 시각.**
/// 미리 알림(resurface) = 게시 시작(lead). 완료·catch-up은 둘 다 같은 간격 전진(lead 보존).
final class RecurrenceCycleTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func d(_ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: day, hour: h, minute: min))!
    }
    /// 되풀이 항목 — 마감(회차 시각) 필수, 미리 알림(게시 시작) 선택.
    private func item(_ unit: String, due: String, resurface: String? = nil, auto: String? = nil) -> ResolvedItem {
        var f: [String: String] = ["type": "recurrence", "recur": unit, "due": due, "raw": "약"]
        if let resurface { f["resurface"] = resurface }
        if let auto { f["recurAuto"] = auto }
        return ResolvedItem(id: "a", fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }

    func testStep() {
        XCTAssertEqual(Recurrence.step(d(8, 3, 8), by: .daily, calendar: utc), d(8, 4, 8))
        XCTAssertEqual(Recurrence.step(d(8, 3, 8), by: .weekly, calendar: utc), d(8, 10, 8))
        XCTAssertEqual(Recurrence.step(d(8, 3, 8), by: .yearly, calendar: utc), utc.date(from: DateComponents(year: 2027, month: 8, day: 3, hour: 8))!)
    }

    // 완료 전진 — 마감 앵커. 온타임·이른·밀림 모두 다음 미래 회차로.
    func testCompletionAdvance_onTime_early_behind() {
        // 온타임: 마감 08-03 08:00 회차를 08:05에 완료 → 08-04 08:00
        XCTAssertEqual(Recurrence.completionAdvance(item("daily", due: "2026-08-03T08:00"), now: d(8, 3, 8, 5), calendar: utc)?["due"], "2026-08-04T08:00")
        // 이른 완료: 07:00 → 08-04 08:00
        XCTAssertEqual(Recurrence.completionAdvance(item("daily", due: "2026-08-03T08:00"), now: d(8, 3, 7), calendar: utc)?["due"], "2026-08-04T08:00")
        // 밀림: 마감 08-01, 08-03 14:00 완료 → 08-04 08:00 (놓친 날 건너뜀)
        XCTAssertEqual(Recurrence.completionAdvance(item("daily", due: "2026-08-01T08:00"), now: d(8, 3, 14), calendar: utc)?["due"], "2026-08-04T08:00")
    }

    // ★ lead 보존 — 마감·미리 알림이 같은 간격만큼 함께 전진(8시 약 · 7시 알림 → 다음날 8시 · 7시).
    func testCompletionAdvance_preservesLead() {
        let c = Recurrence.completionAdvance(item("daily", due: "2026-08-03T08:00", resurface: "2026-08-03T07:00"), now: d(8, 3, 8, 5), calendar: utc)
        XCTAssertEqual(c?["due"], "2026-08-04T08:00")
        XCTAssertEqual(c?["resurface"], "2026-08-04T07:00")   // lead(1시간) 보존
    }

    func testCompletionAdvance_dateOnly() {
        XCTAssertEqual(Recurrence.completionAdvance(item("daily", due: "2026-08-03"), now: d(8, 3, 14), calendar: utc)?["due"], "2026-08-04")
    }

    // ★ lead 0 (미리 알림 없음) — 실데이터 3개 케이스. 완료 시 **마감만 전진, 미리 알림엔 아무것도 안 들어감.**
    func testCompletionAdvance_noResurface_onlyDueAdvances() {
        let c = Recurrence.completionAdvance(item("daily", due: "2026-08-03T08:00"), now: d(8, 3, 8, 5), calendar: utc)
        XCTAssertEqual(c?["due"], "2026-08-04T08:00")
        XCTAssertNil(c?["resurface"], "미리 알림 없으면 전진값에도 미리 알림 없음(계속 비어 있음)")
    }
    func testCompletionChanges_noResurface_dueAndLastDoneOnly() {
        let c = Recurrence.completionChanges(for: item("daily", due: "2026-08-03T08:00"), now: d(8, 3, 8, 5), calendar: utc)
        XCTAssertEqual(c["due"], "2026-08-04T08:00")
        XCTAssertNil(c["resurface"])
        XCTAssertNotNil(c[Recurrence.lastDoneKey])
        XCTAssertNil(c["status"])
    }
    // 자정 근처(00:10) 경계 — 01781308 케이스. 완료 시 다음날 같은 시각으로.
    func testCompletionAdvance_nearMidnightBoundary() {
        XCTAssertEqual(Recurrence.completionAdvance(item("daily", due: "2026-08-03T00:10"), now: d(8, 3, 0, 20), calendar: utc)?["due"], "2026-08-04T00:10")
    }

    func testMissed_anchorIsDue() {
        XCTAssertEqual(Recurrence.missed(item("daily", due: "2026-08-01T08:00"), now: d(8, 3, 14), calendar: utc), 2)  // 08-01·08-02
        XCTAssertEqual(Recurrence.missed(item("daily", due: "2026-08-03T08:00"), now: d(8, 3, 14), calendar: utc), 0)  // 오늘 것 아님
        XCTAssertEqual(Recurrence.missed(item("daily", due: "2026-08-05T08:00"), now: d(8, 3, 14), calendar: utc), 0)  // 미래
    }

    // catch-up — 자동완성 값의 귀결(마감·미리 알림 둘 다 전진).
    func testCatchUp_none_noAdvance() {
        XCTAssertNil(Recurrence.catchUpChanges(item("daily", due: "2026-08-01T08:00", auto: "none"), now: d(8, 3, 14), calendar: utc))
    }
    func testCatchUp_noon_advancesBoth() {
        let c = Recurrence.catchUpChanges(item("daily", due: "2026-08-01T08:00", resurface: "2026-08-01T07:00", auto: "noon"), now: d(8, 3, 14), calendar: utc)
        XCTAssertEqual(c?["due"], "2026-08-04T08:00")
        XCTAssertEqual(c?["resurface"], "2026-08-04T07:00")   // lead 보존
    }
    /// **Stage 5-0 (2026-08-04) — 회차가 오기도 전에 넘어갈 수는 없다.**
    /// `noon` + **저녁 마감**이면 임계(12시)가 마감(20시)보다 앞서서 회차가 도착하기도 전에 닫혔다.
    /// 그러면 정작 20시엔 **이미 닫힌 회차**로 알림이 가는 잡음이 된다 → 임계 = `max(자동완성 임계, 회차 시각)`.
    func testCatchUp_noon_thresholdCannotPrecedeCycleTime() {
        let ev = item("daily", due: "2026-08-01T20:00", resurface: "2026-08-01T19:00", auto: "noon")
        // 정오는 지났지만 **회차(20시)는 아직** → 넘어가지 않는다(고치기 전에는 여기서 전진했다).
        XCTAssertNil(Recurrence.catchUpChanges(ev, now: d(8, 1, 12, 30), calendar: utc))
        XCTAssertNil(Recurrence.catchUpChanges(ev, now: d(8, 1, 19, 59), calendar: utc))
        // 회차 시각이 지나면 넘어간다 — lead(1시간)도 같이 전진.
        let c = Recurrence.catchUpChanges(ev, now: d(8, 1, 20, 30), calendar: utc)
        XCTAssertEqual(c?["due"], "2026-08-02T20:00")
        XCTAssertEqual(c?["resurface"], "2026-08-02T19:00")
    }

    /// 아침 마감·날짜만 있는 항목은 **전혀 안 바뀐다**(`max(12:00, 08:00) = 12:00`, `max(12:00, 자정) = 12:00`).
    /// 5-0이 저녁 마감만 건드린다는 회귀선.
    func testCatchUp_noon_morningAndDateOnlyUnchanged() {
        // 아침 마감: 정오 지나면 그 날 회차가 넘어간다(고치기 전과 동일).
        XCTAssertEqual(Recurrence.catchUpChanges(item("daily", due: "2026-08-01T08:00", auto: "noon"),
                                                now: d(8, 1, 12, 30), calendar: utc)?["due"], "2026-08-02T08:00")
        XCTAssertNil(Recurrence.catchUpChanges(item("daily", due: "2026-08-01T08:00", auto: "noon"),
                                              now: d(8, 1, 11, 30), calendar: utc))
        // 날짜만(자정): 정오가 임계 — 불변.
        XCTAssertEqual(Recurrence.catchUpChanges(item("daily", due: "2026-08-01", auto: "noon"),
                                                now: d(8, 1, 12, 30), calendar: utc)?["due"], "2026-08-02")
    }

    /// `endOfDay`는 임계(다음 자정)가 언제나 그 날 회차 시각보다 뒤라 `max`가 no-op — 늦은 밤 마감으로 확인.
    func testCatchUp_endOfDay_maxIsNoOp() {
        let late = item("daily", due: "2026-08-01T23:30", auto: "endOfDay")
        XCTAssertNil(Recurrence.catchUpChanges(late, now: d(8, 1, 23, 45), calendar: utc))          // 아직 그 날
        XCTAssertEqual(Recurrence.catchUpChanges(late, now: d(8, 2, 0, 10), calendar: utc)?["due"],  // 자정 넘김
                       "2026-08-02T23:30")
    }

    func testCatchUp_endOfDay_todayNotYetPassed() {
        XCTAssertNil(Recurrence.catchUpChanges(item("daily", due: "2026-08-03T08:00", auto: "endOfDay"), now: d(8, 3, 14), calendar: utc))
        XCTAssertEqual(Recurrence.catchUpChanges(item("daily", due: "2026-08-03T08:00", auto: "endOfDay"), now: d(8, 4, 1), calendar: utc)?["due"], "2026-08-04T08:00")
    }

    func testCompletionChanges_advancesAndLastDone() {
        let c = Recurrence.completionChanges(for: item("daily", due: "2026-08-03T08:00", resurface: "2026-08-03T07:00"), now: d(8, 3, 8, 5), calendar: utc)
        XCTAssertEqual(c["due"], "2026-08-04T08:00")
        XCTAssertEqual(c["resurface"], "2026-08-04T07:00")
        XCTAssertEqual(c[Recurrence.lastDoneKey], ItemSchedule.dayTimeString(d(8, 3, 8, 5), calendar: utc))
        XCTAssertNil(c["status"])
    }
}
