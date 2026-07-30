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

    /// 마감+미리 알림 둘 다(미리 알림 도래) → **배지는 마감 기준**(며칠 남음은 due로 잰다), 정렬 기준일도 마감.
    func testSplit_badgeUsesDeadline_whenBothPresent() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 0))!
        // 미리 알림 07-20(이미 도래 → 게시됨), 마감 07-30(D-8). 배지는 마감(D-8)이어야 한다.
        let it = item("X", due: "2026-07-30", resurface: "2026-07-20")
        let s = InboxSectionizer.split([it], now: now, calendar: cal)
        XCTAssertEqual(s.upcoming.count, 1)
        XCTAssertEqual(s.upcoming[0].day, "2026-07-30")               // 정렬·표시 기준 = 마감
        XCTAssertEqual(s.upcoming[0].dday, DDay(bucket: .future, days: 8))  // 배지 = 마감 기준 D-8
    }

    /// 마감 지남 + 미리 알림 미래 → **게시는 미리 알림까지 안 됨**(recent로), 하지만 마감 기준 배지는 D+N(지남).
    /// 게시 여부(Stage 2 게이트)와 배지 계산(Stage 1 마감 기준)이 각각 옳게 동작하는지 함께 고정.
    func testSplit_overdueDeadline_futureResurface_gatedOut_butDeadlineOverdue() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 0))!
        let it = item("Y", due: "2026-07-25", resurface: "2026-08-05")   // 마감 5일 지남, 미리 알림 미래
        let s = InboxSectionizer.split([it], now: now, calendar: cal)
        XCTAssertTrue(s.upcoming.isEmpty)                    // 미리 알림 미도래 → 게시 안 됨
        XCTAssertEqual(s.recent.map { $0.id }, ["Y"])        // 유실 아님 — 시점 없는 쪽으로
        // 배지가 만약 떴다면 마감 기준 D+5(지남)이었을 것 — deadlineDay로 확인
        XCTAssertEqual(ItemSchedule.deadlineDay(it), "2026-07-25")
        XCTAssertEqual(DDayCalc.compute(day: "2026-07-25", now: now, calendar: cal),
                       DDay(bucket: .overdue, days: -5))
    }

    /// 미리 알림만(마감 없음)이 **도래한** 경우 → 곧 닥칠 것에 뜨되 **배지 없음**(dday nil).
    /// 어제까지는 미리 알림 날짜로 배지가 붙었다.
    func testSplit_resurfaceOnly_arrived_noBadge() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 0))!
        let it = item("Z", resurface: "2026-07-20")   // 이미 도래
        let s = InboxSectionizer.split([it], now: now, calendar: cal)
        XCTAssertEqual(s.upcoming.map { $0.item.id }, ["Z"])   // 곧 닥칠 것엔 있고
        XCTAssertNil(s.upcoming.first?.dday)                    // 배지는 없다
    }

    // MARK: 게시 게이트 (Stage 2) — 미리 알림 도래 전에는 게시하지 않기

    /// 미리 알림이 **미래** → 게시 안 됨, 시점 없는 쪽으로 이동, 총 개수 보존. (ClassGateTests 7번과 같은 층)
    func testGate_futureResurface_notPublished_countPreserved() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 0))!
        let future = item("F", resurface: "2026-08-06")     // 미도래
        let arrived = item("A", resurface: "2026-07-28")    // 도래
        let s = InboxSectionizer.split([future, arrived], now: now, calendar: cal)
        XCTAssertEqual(s.upcoming.map { $0.item.id }, ["A"])   // 도래한 것만 게시
        XCTAssertEqual(s.recent.map { $0.id }, ["F"])          // 미도래는 시점 없는 쪽으로(유실 아님)
        XCTAssertEqual(s.upcoming.count + s.recent.count, 2)   // 총 개수 보존
    }

    /// 미리 알림이 **오늘/과거** → 게시됨.
    func testGate_todayOrPastResurface_published() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 12))!
        let today = item("T", resurface: "2026-07-30")   // 오늘(늦은 시각이어도)
        let past  = item("P", resurface: "2026-07-25")   // 지남
        let s = InboxSectionizer.split([today, past], now: now, calendar: cal)
        XCTAssertEqual(Set(s.upcoming.map { $0.item.id }), ["T", "P"])
        XCTAssertTrue(s.recent.isEmpty)
    }

    /// 마감만 있고 **먼 미래** → 게시됨(현재 동작 보존 회귀 방지 — 마감은 미리 알림 게이트를 안 탄다).
    func testGate_dueOnlyFarFuture_published() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 0))!
        let it = item("D", due: "2026-12-31")   // 먼 미래 마감, 미리 알림 없음
        let s = InboxSectionizer.split([it], now: now, calendar: cal)
        XCTAssertEqual(s.upcoming.map { $0.item.id }, ["D"])
    }

    /// 미리 알림 미래 + 마감 있음 → 게시 안 됨(1번이 2번보다 앞선다 — 미리 알림이 게이트).
    func testGate_futureResurface_overridesDue() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 0))!
        let it = item("Pr", due: "2026-08-10", resurface: "2026-08-06")   // 약속류(둘 다 씀·미분류 폴백)
        let s = InboxSectionizer.split([it], now: now, calendar: cal)
        XCTAssertTrue(s.upcoming.isEmpty)
        XCTAssertEqual(s.recent.map { $0.id }, ["Pr"])
    }

    func testSplit_allRecentWhenNoDates() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 0))!
        let s = InboxSectionizer.split([item("A"), item("B", due: "none")], now: now, calendar: cal)
        XCTAssertTrue(s.upcoming.isEmpty)
        XCTAssertEqual(s.recent.count, 2)
    }
}
