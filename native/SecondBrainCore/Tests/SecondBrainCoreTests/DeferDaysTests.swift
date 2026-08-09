import XCTest
@testable import SecondBrainCore

/// **미루기 1·3·7일 (2026-08-09)** — 버튼이 셋이 되어도 **규칙은 하나**다.
///
/// `deferBy(days:)` 하나만 두고 `deferSevenDays`는 그 이름 있는 짝으로 남겼다.
/// 여기 시험이 지키는 것은 **"세 버튼이 같은 길을 탄다"** 는 것이다 — 상한에 걸려 당겨지는 것도,
/// 막히는 것도, 마감이 없거나 지났을 때 제약이 없는 것도 **날 수와 무관하게 같은 판정**이어야 한다.
///
/// ⚠️ **완전한 단계 0은 아니다** — 함수가 없던 상태에선 컴파일이 안 되므로 "고치기 전에 실패"를 못 만든다.
/// 다만 **`days: 7`이 옛 `deferSevenDays`와 값·플래그까지 같다**는 것은 진짜 회귀선이다(아래 첫 시험).
final class DeferDaysTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func d(_ m: Int, _ day: Int, _ h: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: day, hour: h))!
    }

    /// **옛 동작 보존** — `deferSevenDays`는 `deferBy(days: 7)`과 **값·플래그가 같아야** 한다.
    /// 목록 스와이프(+7일)가 이 등식 위에 서 있다.
    func testSevenDays_isExactlyDeferBySeven() {
        for due in [nil, "2026-07-20", "2026-08-05", "2026-08-10", "2026-07-31T13:00"] as [String?] {
            for hasTime in [false, true] {
                let now = d(8, 3, 9)
                XCTAssertEqual(ItemSchedule.deferSevenDays(due: due, now: now, resurfaceHasTime: hasTime, calendar: utc),
                               ItemSchedule.deferBy(days: 7, due: due, now: now, resurfaceHasTime: hasTime, calendar: utc),
                               "due=\(due ?? "nil") hasTime=\(hasTime)")
            }
        }
    }

    /// **기준은 오늘이다** — 지금 값이 어디에 있든 **오늘 + N일**이다(미루기의 뜻).
    func testTargetIsTodayPlusN_notCurrentValuePlusN() {
        let now = d(8, 3, 9)
        XCTAssertEqual(ItemSchedule.deferBy(days: 1, due: nil, now: now, calendar: utc), .deferred(to: "2026-08-04", capped: false))
        XCTAssertEqual(ItemSchedule.deferBy(days: 3, due: nil, now: now, calendar: utc), .deferred(to: "2026-08-06", capped: false))
        XCTAssertEqual(ItemSchedule.deferBy(days: 7, due: nil, now: now, calendar: utc), .deferred(to: "2026-08-10", capped: false))
    }

    /// **상한은 셋 다 같은 자리에서 잡는다** — 마감 08-06이면 상한은 08-05(시각 없음).
    /// 1일은 안 걸리고, 3·7일은 걸려 **같은 값으로** 당겨진다.
    func testUpperBound_appliesIdenticallyToAllThree() {
        let now = d(8, 3, 9)
        XCTAssertEqual(ItemSchedule.deferBy(days: 1, due: "2026-08-06", now: now, calendar: utc),
                       .deferred(to: "2026-08-04", capped: false))          // 상한 안
        XCTAssertEqual(ItemSchedule.deferBy(days: 3, due: "2026-08-06", now: now, calendar: utc),
                       .deferred(to: "2026-08-05", capped: true))           // 당겨짐
        XCTAssertEqual(ItemSchedule.deferBy(days: 7, due: "2026-08-06", now: now, calendar: utc),
                       .deferred(to: "2026-08-05", capped: true))           // 같은 값으로 당겨짐
    }

    /// **막히는 것도 셋 다 같다** — 상한이 오늘이거나 지났으면 날 수와 무관하게 `blocked`.
    func testBlocked_sameForAllThree() {
        let now = d(8, 3, 9)
        for n in [1, 3, 7] {
            XCTAssertEqual(ItemSchedule.deferBy(days: n, due: "2026-08-04", now: now, calendar: utc),
                           .blocked(cap: "2026-08-03"), "days=\(n)")
        }
    }

    /// **마감이 없거나 지났으면 제약 없음** — 셋 다 오늘+N일 그대로.
    func testNoDueOrPastDue_unconstrained() {
        let now = d(8, 3, 9)
        for (n, day) in [(1, "2026-08-04"), (3, "2026-08-06"), (7, "2026-08-10")] {
            XCTAssertEqual(ItemSchedule.deferBy(days: n, due: "2026-07-20", now: now, calendar: utc),
                           .deferred(to: day, capped: false), "days=\(n)")
        }
    }

    /// **시각 있는 미리 알림은 상한이 마감 당일** — 이것도 날 수와 무관하게 같이 움직인다.
    func testHasTime_upperBoundIsDueDay_forAllThree() {
        let now = d(8, 3, 9)
        XCTAssertEqual(ItemSchedule.deferBy(days: 3, due: "2026-08-05T19:00", now: now, resurfaceHasTime: true, calendar: utc),
                       .deferred(to: "2026-08-05", capped: true))
        XCTAssertEqual(ItemSchedule.deferBy(days: 7, due: "2026-08-05T19:00", now: now, resurfaceHasTime: true, calendar: utc),
                       .deferred(to: "2026-08-05", capped: true))
        XCTAssertEqual(ItemSchedule.deferBy(days: 1, due: "2026-08-05T19:00", now: now, resurfaceHasTime: true, calendar: utc),
                       .deferred(to: "2026-08-04", capped: false))
    }
}
