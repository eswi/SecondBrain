import XCTest
@testable import SecondBrainCore

final class InboxSectionsTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func item(_ id: String, due: String? = nil, resurface: String? = nil,
                      created: Int64 = 1) -> ResolvedItem {
        var f: [String: String] = ["raw": "\(id) 내용"]
        if let due { f["due"] = due }
        if let resurface { f["resurface"] = resurface }
        return ResolvedItem(id: id, fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: created, counter: 0, deviceId: "t"))
    }

    // MARK: ItemSchedule.effectiveDay

    func testEffectiveDay_resurfacePreferredOverDue() {
        XCTAssertEqual(ItemSchedule.effectiveDay(item("A", due: "2026-07-30", resurface: "2026-07-18")), "2026-07-18")
        XCTAssertEqual(ItemSchedule.effectiveDay(item("B", due: "2026-07-20")), "2026-07-20")
        XCTAssertNil(ItemSchedule.effectiveDay(item("C", due: "none", resurface: "weekly")))
        XCTAssertNil(ItemSchedule.effectiveDay(item("D")))
    }

    // MARK: DDay

    func testDDay_buckets() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 10))!
        XCTAssertEqual(DDayCalc.compute(day: "2026-07-15", now: now, calendar: cal),
                       DDay(bucket: .overdue, days: -2))
        XCTAssertEqual(DDayCalc.compute(day: "2026-07-17", now: now, calendar: cal),
                       DDay(bucket: .today, days: 0))
        XCTAssertEqual(DDayCalc.compute(day: "2026-07-24", now: now, calendar: cal),
                       DDay(bucket: .future, days: 7))
        XCTAssertNil(DDayCalc.compute(day: "weekly", now: now, calendar: cal))
    }

    func testDDay_ignoresTimeOfDay() {
        let cal = utc
        // 오늘 늦은 시각이어도 오늘 날짜면 D-0
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 23, minute: 59))!
        XCTAssertEqual(DDayCalc.compute(day: "2026-07-18", now: now, calendar: cal)?.days, 1)
    }

    // MARK: InboxSectionizer.split

    func testSplit_upcomingSortedRecentPreserved() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 0))!
        let items = [
            item("R1", created: 100),                 // 시점 없음 (최근, 먼저 들어온 순서 유지)
            item("U_future", due: "2026-07-24"),      // D+7
            item("U_overdue", due: "2026-07-10"),     // 지남
            item("R2", created: 50),                  // 시점 없음
            item("U_today", resurface: "2026-07-17"), // 오늘
        ]
        let s = InboxSectionizer.split(items, now: now, calendar: cal)

        // upcoming: 지남 → 오늘 → 미래
        XCTAssertEqual(s.upcoming.map { $0.item.id }, ["U_overdue", "U_today", "U_future"])
        XCTAssertEqual(s.upcoming.map { $0.dday.bucket }, [.overdue, .today, .future])
        // recent: 입력 순서 유지 (정렬 안 건드림)
        XCTAssertEqual(s.recent.map { $0.id }, ["R1", "R2"])
    }

    func testSplit_allRecentWhenNoDates() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 0))!
        let s = InboxSectionizer.split([item("A"), item("B", due: "none")], now: now, calendar: cal)
        XCTAssertTrue(s.upcoming.isEmpty)
        XCTAssertEqual(s.recent.count, 2)
    }
}
