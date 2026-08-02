import XCTest
@testable import SecondBrainCore

/// 규칙 1 시각화(2026-08-03) — 같은 규칙, 시각 유무로 적용만 다름.
/// 시각 있으면 `미리 알림 ≤ 마감`(이후만 위반). date-only는 하루 전(RuleOneTests가 고정).
final class RuleOneTimeTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func now(_ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }
    private func v(_ r: String, _ due: String, _ now: Date) -> Bool {
        ItemSchedule.violatesRule1(resurface: r, due: due, now: now, calendar: utc)
    }

    func testTimed_beforeDue_ok() {
        // 7시 미리 알림 + 8시 마감 (같은 날) → 위반 아님 (lead-time)
        XCTAssertFalse(v("2026-08-10T07:00", "2026-08-10T08:00", now(8, 2)))
    }
    func testTimed_equalDue_ok() {
        // 정각(미리 알림 = 마감) → 허용 (실질 lead 0이지만 위반 아님)
        XCTAssertFalse(v("2026-08-10T08:00", "2026-08-10T08:00", now(8, 2)))
    }
    func testTimed_afterDue_violation() {
        // 마감 이후 → 위반
        XCTAssertTrue(v("2026-08-10T09:00", "2026-08-10T08:00", now(8, 2)))
    }
    func testDateOnlyResurface_stillNeedsDayBefore() {
        // 미리 알림이 date-only면 마감에 시각이 있어도 하루 전 규칙(같은 날은 위반)
        XCTAssertTrue(v("2026-08-10", "2026-08-10T08:00", now(8, 2)))
        XCTAssertFalse(v("2026-08-09", "2026-08-10T08:00", now(8, 2)))
    }
    func testTimedDueToday_ruleApplies() {
        // 마감 오늘 08시, 지금 07시 → 마감 미래라 규칙 적용(옛 날짜 게이트론 안 걸리던 것)
        XCTAssertTrue(v("2026-08-02T09:00", "2026-08-02T08:00", now(8, 2, 7)))   // 마감 이후 → 위반
        XCTAssertFalse(v("2026-08-02T07:30", "2026-08-02T08:00", now(8, 2, 7)))  // 마감 이전 → OK
    }

    func testUpperBound_hasTime_allowsSameDay() {
        let ub = ItemSchedule.resurfaceUpperBound(due: "2026-08-10T08:00", now: now(8, 2), resurfaceHasTime: true, calendar: utc)
        XCTAssertEqual(ub.map { ItemSchedule.dayString($0, calendar: utc) }, "2026-08-10")   // 같은 날까지
        let ubDate = ItemSchedule.resurfaceUpperBound(due: "2026-08-10T08:00", now: now(8, 2), resurfaceHasTime: false, calendar: utc)
        XCTAssertEqual(ubDate.map { ItemSchedule.dayString($0, calendar: utc) }, "2026-08-09") // 하루 전
    }
}
