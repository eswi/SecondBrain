import XCTest
@testable import SecondBrainCore

/// 규칙 1 — 미리 알림은 마감보다 최소 하루 빠르게. 마감이 **미래**일 때만 적용.
/// 규칙은 Core(`ItemSchedule`) 한 곳에 있고 세 곳(날짜 선택·자동 분류·미루기)이 이걸 쓴다.
final class RuleOneTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func now(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: 0))!
    }

    // MARK: 상한(마감 − 1일)

    func testUpperBound_future_isDueMinusOne() {
        let ub = ItemSchedule.resurfaceUpperBound(due: "2026-08-10", now: now(2026, 7, 30), calendar: utc)
        XCTAssertEqual(ub.map { ItemSchedule.dayString($0, calendar: utc) }, "2026-08-09")
    }
    func testUpperBound_todayOrPast_isNil() {
        XCTAssertNil(ItemSchedule.resurfaceUpperBound(due: "2026-07-30", now: now(2026, 7, 30), calendar: utc)) // 오늘
        XCTAssertNil(ItemSchedule.resurfaceUpperBound(due: "2026-07-20", now: now(2026, 7, 30), calendar: utc)) // 과거
    }
    func testUpperBound_noDue_isNil() {
        XCTAssertNil(ItemSchedule.resurfaceUpperBound(due: nil, now: now(2026, 7, 30), calendar: utc))
        XCTAssertNil(ItemSchedule.resurfaceUpperBound(due: "none", now: now(2026, 7, 30), calendar: utc))
    }

    // MARK: 위반 판정 — 같은 날 위반, 마감−1일 통과, 마감 지남 제약 없음

    func testViolates_sameDay_isViolation() {
        XCTAssertTrue(ItemSchedule.violatesRule1(resurface: "2026-08-10", due: "2026-08-10",
                                                 now: now(2026, 7, 30), calendar: utc))
    }
    func testViolates_dueMinusOne_passes() {
        XCTAssertFalse(ItemSchedule.violatesRule1(resurface: "2026-08-09", due: "2026-08-10",
                                                  now: now(2026, 7, 30), calendar: utc))
    }
    func testViolates_laterThanDue_isViolation() {
        XCTAssertTrue(ItemSchedule.violatesRule1(resurface: "2026-08-12", due: "2026-08-10",
                                                 now: now(2026, 7, 30), calendar: utc))
    }
    func testViolates_duePast_noConstraint() {
        // 마감이 지났으면 제약 없음 — 지난 것을 미루는 건 필요한 동작(같은 날이어도 위반 아님).
        XCTAssertFalse(ItemSchedule.violatesRule1(resurface: "2026-07-20", due: "2026-07-20",
                                                  now: now(2026, 7, 30), calendar: utc))
    }
    func testViolates_noResurfaceOrDue_false() {
        XCTAssertFalse(ItemSchedule.violatesRule1(resurface: nil, due: "2026-08-10",
                                                  now: now(2026, 7, 30), calendar: utc))
        XCTAssertFalse(ItemSchedule.violatesRule1(resurface: "2026-08-05", due: nil,
                                                  now: now(2026, 7, 30), calendar: utc))
    }

    // MARK: 미루기(+7일) — 당겨짐 / 막힘 / 그대로 네 경우

    /// 마감 없음/지남 → 오늘+7일 그대로.
    func testDefer_noDue_and_pastDue_plainSeven() {
        let n = now(2026, 7, 30)
        XCTAssertEqual(ItemSchedule.deferSevenDays(due: nil, now: n, calendar: utc),
                       .deferred(to: "2026-08-06", capped: false))
        XCTAssertEqual(ItemSchedule.deferSevenDays(due: "2026-07-20", now: n, calendar: utc),
                       .deferred(to: "2026-08-06", capped: false))
    }
    /// 마감 하루 전이 아직 미래고 오늘+7일이 그 상한 안 → 그대로.
    func testDefer_withinBound_plainSeven() {
        // 마감 08-10 → 상한 08-09, 오늘+7=08-06 ≤ 08-09 → 그대로.
        XCTAssertEqual(ItemSchedule.deferSevenDays(due: "2026-08-10", now: now(2026, 7, 30), calendar: utc),
                       .deferred(to: "2026-08-06", capped: false))
    }
    /// 오늘+7일이 상한을 넘음 → 상한(마감−1일)까지 당겨서 미룸(capped).
    func testDefer_overBound_cappedToDueMinusOne() {
        // 마감 08-05 → 상한 08-04, 오늘+7=08-06 > 08-04 → 08-04로 당김.
        XCTAssertEqual(ItemSchedule.deferSevenDays(due: "2026-08-05", now: now(2026, 7, 30), calendar: utc),
                       .deferred(to: "2026-08-04", capped: true))
    }
    /// 마감 하루 전이 오늘/과거 → 미루지 않음(blocked).
    func testDefer_deadlineImminent_blocked() {
        // 마감 07-31(내일) → 상한 07-30=오늘 → 막힘.
        XCTAssertEqual(ItemSchedule.deferSevenDays(due: "2026-07-31", now: now(2026, 7, 30), calendar: utc),
                       .blocked(cap: "2026-07-30"))
    }
}
