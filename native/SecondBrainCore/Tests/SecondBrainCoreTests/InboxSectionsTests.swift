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

    // MARK: ItemSchedule.publishDay (게시 시작일 = 미리 알림 우선, 없으면 마감)

    func testPublishDay_resurfacePreferredOverDue() {
        XCTAssertEqual(ItemSchedule.publishDay(item("A", due: "2026-07-30", resurface: "2026-07-18")), "2026-07-18")
        XCTAssertEqual(ItemSchedule.publishDay(item("B", due: "2026-07-20")), "2026-07-20")
        XCTAssertNil(ItemSchedule.publishDay(item("C", due: "none", resurface: "weekly")))
        XCTAssertNil(ItemSchedule.publishDay(item("D")))
    }

    /// resurface의 새 기본값 "none"이 레거시 "weekly"와 **동일하게** '날짜 없음'으로 처리되는지.
    /// (weekly는 반복 기능이 아니라 "날짜 없음"의 동의어였다 — 신규 값은 none뿐, weekly는 읽기 호환.)
    func testPublishDay_noneEqualsWeekly_bothNoTime() {
        // due도 resurface도 시점 없음 → nil (none·weekly 동치)
        XCTAssertNil(ItemSchedule.publishDay(item("N1", due: "none", resurface: "none")))
        XCTAssertNil(ItemSchedule.publishDay(item("N2", resurface: "none")))
        XCTAssertEqual(ItemSchedule.publishDay(item("N3", due: "none", resurface: "weekly")),
                       ItemSchedule.publishDay(item("N4", due: "none", resurface: "none")))  // 둘 다 nil = 동일
        // resurface가 none이면 막지 말고 due로 폴백해야 한다("weekly가 아니면 날짜" 오인 방지 회귀 가드)
        XCTAssertEqual(ItemSchedule.publishDay(item("N5", due: "2026-07-20", resurface: "none")), "2026-07-20")
    }

    // MARK: ItemSchedule.deadlineDay (마감 = due만 본다, 미리 알림 무시)

    /// 마감은 **due만** 본다 — 미리 알림(resurface)이 있어도 마감일은 due 그대로.
    func testDeadlineDay_dueOnly_ignoresResurface() {
        XCTAssertEqual(ItemSchedule.deadlineDay(item("A", due: "2026-07-30", resurface: "2026-07-18")), "2026-07-30")
        XCTAssertEqual(ItemSchedule.deadlineDay(item("B", due: "2026-07-20")), "2026-07-20")
        // 미리 알림만 있고 마감이 없으면 → 마감 없음(nil). (배지를 띄우지 않는 근거)
        XCTAssertNil(ItemSchedule.deadlineDay(item("C", resurface: "2026-07-18")))
        XCTAssertNil(ItemSchedule.deadlineDay(item("D", due: "none", resurface: "2026-07-18")))
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
            item("U_today", resurface: "2026-07-17"), // 오늘(미리 알림만 → 게시 시작일로 정렬, 배지는 없음)
        ]
        let s = InboxSectionizer.split(items, now: now, calendar: cal)

        // upcoming: 지남 → 오늘 → 미래 (정렬은 deadlineDay?→publishDay 기준 — 미리 알림만인 U_today도 제자리)
        XCTAssertEqual(s.upcoming.map { $0.item.id }, ["U_overdue", "U_today", "U_future"])
        // 배지는 마감(deadlineDay) 기준 — U_today는 마감이 없어 nil(배지 없음)
        XCTAssertEqual(s.upcoming.map { $0.dday?.bucket }, [.overdue, nil, .future])
        // recent: 입력 순서 유지 (정렬 안 건드림)
        XCTAssertEqual(s.recent.map { $0.id }, ["R1", "R2"])
    }

    // MARK: 역할 분리 — 배지는 마감 기준, 정렬은 마감→게시 폴백 (Stage 1)

    /// 마감+미리 알림 둘 다 → **배지는 마감 기준**(며칠 남음은 due로 잰다), 정렬 기준일도 마감.
    func testSplit_badgeUsesDeadline_whenBothPresent() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 0))!
        // 마감 07-25(D-7), 미리 알림 07-20(게시 시작). 배지는 마감(D-7)이어야 한다.
        let it = item("X", due: "2026-07-25", resurface: "2026-07-20")
        let s = InboxSectionizer.split([it], now: now, calendar: cal)
        XCTAssertEqual(s.upcoming.count, 1)
        XCTAssertEqual(s.upcoming[0].day, "2026-07-25")               // 정렬·표시 기준 = 마감
        XCTAssertEqual(s.upcoming[0].dday, DDay(bucket: .future, days: 7))  // 배지 = 마감 기준 D-7
    }

    /// 마감 지남 + 미리 알림 미래 → 배지는 마감 기준 D+N(지남). (게시 여부는 Stage 2 관할 — 여기선 배지만)
    func testSplit_overdueDeadline_futureResurface_badgeIsOverdue() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 0))!
        let it = item("Y", due: "2026-07-25", resurface: "2026-08-05")   // 마감은 5일 지남
        let s = InboxSectionizer.split([it], now: now, calendar: cal)
        XCTAssertEqual(s.upcoming.count, 1)
        XCTAssertEqual(s.upcoming[0].dday, DDay(bucket: .overdue, days: -5))  // D+5(지남)
    }

    /// 미리 알림만(마감 없음) → 곧 닥칠 것에 뜨되 **배지 없음**(dday nil). 어제까지는 미리 알림 날짜로 배지가 붙었다.
    func testSplit_resurfaceOnly_noBadge() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 0))!
        let it = item("Z", resurface: "2026-07-20")
        let s = InboxSectionizer.split([it], now: now, calendar: cal)
        XCTAssertEqual(s.upcoming.map { $0.item.id }, ["Z"])   // 곧 닥칠 것엔 있고
        XCTAssertNil(s.upcoming.first?.dday)                    // 배지는 없다
    }

    func testSplit_allRecentWhenNoDates() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 0))!
        let s = InboxSectionizer.split([item("A"), item("B", due: "none")], now: now, calendar: cal)
        XCTAssertTrue(s.upcoming.isEmpty)
        XCTAssertEqual(s.recent.count, 2)
    }
}
