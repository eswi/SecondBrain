import XCTest
@testable import SecondBrainCore

/// Stage 4 (양력 반복) — 회차 계산(순수 함수). 앵커 = 미리 알림(resurface).
final class RecurrenceCycleTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func d(_ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: day, hour: h, minute: min))!
    }
    private func item(_ unit: String, resurface: String, auto: String? = nil) -> ResolvedItem {
        var f: [String: String] = ["type": "recurrence", "recur": unit, "resurface": resurface, "raw": "약"]
        if let auto { f["recurAuto"] = auto }
        return ResolvedItem(id: "a", fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }

    func testStep() {
        XCTAssertEqual(Recurrence.step(d(8, 3, 8), by: .daily, calendar: utc), d(8, 4, 8))
        XCTAssertEqual(Recurrence.step(d(8, 3, 8), by: .weekly, calendar: utc), d(8, 10, 8))
        XCTAssertEqual(Recurrence.step(d(8, 3, 8), by: .yearly, calendar: utc), utc.date(from: DateComponents(year: 2027, month: 8, day: 3, hour: 8))!)
    }

    // 완료 시 다음 회차 — 온타임·이른 완료·밀린 경우 모두 "다음 미래 회차"로.
    func testAdvancedResurface_onTime_early_behind() {
        // 온타임: 08-03 08:00 회차를 08:05에 완료 → 08-04 08:00
        XCTAssertEqual(Recurrence.advancedResurface(item("daily", resurface: "2026-08-03T08:00"), now: d(8, 3, 8, 5), calendar: utc), "2026-08-04T08:00")
        // 이른 완료: 07:00에 완료해도 → 08-04 08:00 (오늘 것 넘어감)
        XCTAssertEqual(Recurrence.advancedResurface(item("daily", resurface: "2026-08-03T08:00"), now: d(8, 3, 7), calendar: utc), "2026-08-04T08:00")
        // 밀림: 08-01 회차인데 08-03 14:00에 완료 → 08-04 08:00 (놓친 날 건너뜀)
        XCTAssertEqual(Recurrence.advancedResurface(item("daily", resurface: "2026-08-01T08:00"), now: d(8, 3, 14), calendar: utc), "2026-08-04T08:00")
    }

    func testAdvancedResurface_dateOnly_keepsDateOnly() {
        XCTAssertEqual(Recurrence.advancedResurface(item("daily", resurface: "2026-08-03"), now: d(8, 3, 14), calendar: utc), "2026-08-04")
    }

    func testMissedCount() {
        XCTAssertEqual(Recurrence.missedCount(base: d(8, 1, 8), unit: .daily, now: d(8, 3, 14), calendar: utc), 2)  // 08-01·08-02
        XCTAssertEqual(Recurrence.missedCount(base: d(8, 3, 8), unit: .daily, now: d(8, 3, 14), calendar: utc), 0)  // 오늘 것은 놓침 아님
        XCTAssertEqual(Recurrence.missedCount(base: d(8, 5, 8), unit: .daily, now: d(8, 3, 14), calendar: utc), 0)  // 미래
    }

    // catch-up — 자동완성 값의 귀결.
    func testCatchUp_none_noAdvance() {
        XCTAssertNil(Recurrence.catchUpResurface(item("daily", resurface: "2026-08-01T08:00", auto: "none"), now: d(8, 3, 14), calendar: utc))
    }
    func testCatchUp_noon_advancesPastNoonOccurrences() {
        // 08-01~08-03 회차의 정오가 지남 → 08-04로
        XCTAssertEqual(Recurrence.catchUpResurface(item("daily", resurface: "2026-08-01T08:00", auto: "noon"), now: d(8, 3, 14), calendar: utc), "2026-08-04T08:00")
    }
    func testCatchUp_endOfDay_todayNotYetPassed() {
        // 08-03 회차, endOfDay 임계 = 08-04 자정. 08-03 14:00엔 아직 안 지남 → 전진 없음
        XCTAssertNil(Recurrence.catchUpResurface(item("daily", resurface: "2026-08-03T08:00", auto: "endOfDay"), now: d(8, 3, 14), calendar: utc))
        // 08-04 01:00엔 08-03 것 지남 → 08-04로
        XCTAssertEqual(Recurrence.catchUpResurface(item("daily", resurface: "2026-08-03T08:00", auto: "endOfDay"), now: d(8, 4, 1), calendar: utc), "2026-08-04T08:00")
    }

    func testCompletionChanges_advancesResurface() {
        let c = Recurrence.completionChanges(for: item("daily", resurface: "2026-08-03T08:00"), now: d(8, 3, 8, 5), calendar: utc)
        XCTAssertEqual(c["resurface"], "2026-08-04T08:00")             // 다음 회차 → 게이트가 숨김
        XCTAssertEqual(c[Recurrence.lastDoneKey], ItemSchedule.dayTimeString(d(8, 3, 8, 5), calendar: utc))
        XCTAssertNil(c["status"])
    }
}
