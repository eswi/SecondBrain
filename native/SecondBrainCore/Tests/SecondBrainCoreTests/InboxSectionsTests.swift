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
        // 하루 경계는 자정 기준 — 오늘 **23:59**여도 "오늘"인 미리 알림은 게시된다(주석이 실제 시각과 맞아야 한다).
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 23, minute: 59))!
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

    // MARK: 게시 게이트 — 함수 직접 (위 게이트 테스트는 전부 split 경유였다)

    /// `ItemSchedule.isPublished`를 **직접** 고정한다. 위의 게이트 테스트들은 `InboxSectionizer.split`을 거치므로
    /// 게이트가 깨져도 정렬·섹션 쪽 코드가 우연히 가려줄 수 있다. 판정 함수 자체의 계약을 한 자리에 못박는다.
    /// 계약: ① 미리 알림이 유효한 날짜면 오늘/과거만 게시 ② 아니면 마감이 유효하면 게시 ③ 그 외 안 함.
    func testIsPublished_directContract() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 10))!

        // ① 미리 알림 우선 — 미래면 마감이 (심지어 이미 지났어도) 있어도 게시 안 함. 실데이터 「T 우주」 조합.
        XCTAssertFalse(ItemSchedule.isPublished(item("A", resurface: "2026-08-06"), now: now, calendar: cal))
        XCTAssertFalse(ItemSchedule.isPublished(item("T", due: "2026-07-26", resurface: "2026-08-06"),
                                                now: now, calendar: cal))
        XCTAssertTrue(ItemSchedule.isPublished(item("B", resurface: "2026-07-30"), now: now, calendar: cal))  // 오늘
        XCTAssertTrue(ItemSchedule.isPublished(item("C", resurface: "2026-07-29"), now: now, calendar: cal))  // 과거

        // ② 마감만 있으면 먼 미래여도 게시 — 미리 알림은 **옵트인 지연 장치**이므로 안 넣은 항목 동작은 불변이어야 한다.
        XCTAssertTrue(ItemSchedule.isPublished(item("E", due: "2027-12-31"), now: now, calendar: cal))
        XCTAssertTrue(ItemSchedule.isPublished(item("F", due: "2026-07-01"), now: now, calendar: cal))  // 지난 마감도

        // ③ 날짜가 없으면 게시 안 함.
        XCTAssertFalse(ItemSchedule.isPublished(item("I"), now: now, calendar: cal))
        XCTAssertFalse(ItemSchedule.isPublished(item("J", due: "none", resurface: "none"), now: now, calendar: cal))
    }

    /// 자정 경계 — 오늘 **23:59**에도 오늘자 미리 알림은 게시된다(판정은 시각이 아니라 날 단위).
    func testIsPublished_resurfaceToday_lateInDay() {
        let cal = utc
        let late = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 23, minute: 59))!
        XCTAssertTrue(ItemSchedule.isPublished(item("D", resurface: "2026-07-30"), now: late, calendar: cal))
    }

    /// 게이트 레벨에서도 `"none"`·`"weekly"`는 날짜가 아니다 → 미리 알림 칸이 빈 것과 같고, 마감으로 판정한다.
    /// (`publishDay` 레벨 동치는 위에서 봤지만, 게이트가 "weekly가 아니면 날짜"로 오인하면 미래 마감이 막힌다.)
    func testIsPublished_noneOrWeeklyResurface_judgedByDue() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 10))!
        XCTAssertTrue(ItemSchedule.isPublished(item("G", due: "2026-08-31", resurface: "none"),
                                               now: now, calendar: cal))
        XCTAssertTrue(ItemSchedule.isPublished(item("H", due: "2026-08-31", resurface: "weekly"),
                                               now: now, calendar: cal))
    }

    // MARK: 값은 안 지우고 효과만 막는다 — 휴면 후 날이 오면 저절로 게시

    /// **이 규칙의 유일한 그물.** 게시 게이트는 항목을 지우거나 날짜를 비우는 게 아니라 *효과만* 막는다:
    /// ① 게시 안 된 항목의 `due`·`resurface` **값이 그대로 남아 있고**(휴면)
    /// ② 미리 알림 날이 오면 **저절로 게시**되며 ③ 그때 배지는 여전히 **마감 기준**이다.
    /// 값을 지우는 구현으로 바뀌면 ①이, 게이트가 한 번 막고 안 풀면 ②가 여기서 깨진다.
    func testNotLost_valuesKept_publishesWhenDayArrives() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 10))!
        let it = item("X", due: "2026-08-31", resurface: "2026-08-10")   // 미리 알림 미래 → 미도래

        let before = InboxSectionizer.split([it], now: now, calendar: cal)
        XCTAssertTrue(before.upcoming.isEmpty)                            // 아직 안 뜬다
        XCTAssertEqual(before.recent.first?.due, "2026-08-31")            // 값 보존 — 마감
        XCTAssertEqual(before.recent.first?.resurface, "2026-08-10")      // 값 보존 — 미리 알림

        let arrival = cal.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 0))!
        let after = InboxSectionizer.split([it], now: arrival, calendar: cal)
        XCTAssertEqual(after.upcoming.map { $0.item.id }, ["X"])          // 그 날 저절로 게시
        XCTAssertEqual(after.upcoming[0].dday, DDay(bucket: .future, days: 21))  // 배지는 여전히 마감 기준
    }

    func testSplit_allRecentWhenNoDates() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 0))!
        let s = InboxSectionizer.split([item("A"), item("B", due: "none")], now: now, calendar: cal)
        XCTAssertTrue(s.upcoming.isEmpty)
        XCTAssertEqual(s.recent.count, 2)
    }
}
