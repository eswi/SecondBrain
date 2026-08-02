import XCTest
@testable import SecondBrainCore

/// 시각(시·분) 도입 — Stage 1(엔진: parseDay 확장 + timeOfDay + planner).
/// recurrence-design.md §6-A/§6-B. 방식(a): 날짜 칸 값 형식 확장.
/// 진앙 = ItemSchedule.parseDay 하나. 실패는 에러가 아니라 "조용한 강등"이라 여기서 테스트로 잡는다.
final class TimeOfDayTests: XCTestCase {

    // UTC 고정 — 로컬 타임존/DST에 흔들리지 않게(기존 NotificationPlannerTests와 동일 관례).
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    // 오늘 = 2026-08-02 00:00 UTC
    private func today() -> Date { utc.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 0))! }

    private func item(_ id: String, due: String? = nil, resurface: String? = nil, type: String? = nil) -> ResolvedItem {
        var f: [String: String] = ["raw": "\(id) 내용"]
        if let due { f["due"] = due }
        if let resurface { f["resurface"] = resurface }
        if let type { f["type"] = type }
        return ResolvedItem(id: id, fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }

    // MARK: 1) parseDay / timeOfDay 단위 — 읽기 관대(공백·T·date-only)

    func testParseDay_dateOnly_unchanged_midnight() {
        let cal = utc
        let d = ItemSchedule.parseDay("2026-08-05", calendar: cal)
        XCTAssertEqual(d, cal.date(from: DateComponents(year: 2026, month: 8, day: 5)))   // 자정
        XCTAssertNil(ItemSchedule.timeOfDay("2026-08-05"))                                 // 시각 없음
    }

    func testParseDay_withTime_bothSeparators() {
        let cal = utc
        let expect = cal.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 19, minute: 0))
        XCTAssertEqual(ItemSchedule.parseDay("2026-08-05T19:00", calendar: cal), expect)  // 표준형 T
        XCTAssertEqual(ItemSchedule.parseDay("2026-08-05 19:00", calendar: cal), expect)  // 공백도 관대
        XCTAssertEqual(ItemSchedule.timeOfDay("2026-08-05T19:00")?.hour, 19)
        XCTAssertEqual(ItemSchedule.timeOfDay("2026-08-05 19:00")?.minute, 0)
    }

    func testParseDay_sameDay_regardlessOfTime() {
        let cal = utc
        let a = cal.startOfDay(for: ItemSchedule.parseDay("2026-08-05", calendar: cal)!)
        let b = cal.startOfDay(for: ItemSchedule.parseDay("2026-08-05T19:00", calendar: cal)!)
        XCTAssertEqual(a, b)   // 시각 유무와 무관하게 같은 날
    }

    // 유실 방지: 시각 부분만 깨져도 날짜는 살린다(자정), timeOfDay만 nil.
    func testParseDay_brokenTime_keepsDate_noSilentDemotion() {
        let cal = utc
        let midnight = cal.date(from: DateComponents(year: 2026, month: 8, day: 5))
        XCTAssertEqual(ItemSchedule.parseDay("2026-08-05T25:99", calendar: cal), midnight) // 범위 밖 → 날짜 살림
        XCTAssertEqual(ItemSchedule.parseDay("2026-08-05Tgarbage", calendar: cal), midnight)
        XCTAssertNil(ItemSchedule.timeOfDay("2026-08-05T25:99"))
    }

    func testParseDay_garbage_nil() {
        XCTAssertNil(ItemSchedule.parseDay("garbage", calendar: utc))
        XCTAssertNil(ItemSchedule.parseDay("2026-08", calendar: utc))
    }

    // MARK: 2) 양성 — 있어야 할 자리에 실제로 나타난다

    func testPositive_deadlineWithTime_computesDDay() {
        // 마감 "2026-08-05 19:00" → 오늘(08-02) 기준 D-3
        let it = item("A", due: "2026-08-05T19:00")
        let day = ItemSchedule.deadlineDay(it)!
        let dd = DDayCalc.compute(day: day, now: today(), calendar: utc)!
        XCTAssertEqual(dd.days, 3)
        XCTAssertEqual(dd.bucket, .future)
    }

    func testResurfaceWithTime_publishedFromThatTime() {
        // 미리 알림 "2026-08-02 08:00" → **그 시각(08:00)부터** 게시(시각 인지, #3). 전엔 아직.
        let it = item("B", resurface: "2026-08-02T08:00")
        let before = utc.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 7))!
        let after = utc.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 9))!
        XCTAssertFalse(ItemSchedule.isPublished(it, now: before, calendar: utc))
        XCTAssertTrue(ItemSchedule.isPublished(it, now: after, calendar: utc))
    }

    func testPositive_resurfaceTomorrowWithTime_notPublishedToday() {
        // 미리 알림 "2026-08-03 08:00" → 오늘 게시 안 됨
        let it = item("C", resurface: "2026-08-03T08:00")
        XCTAssertFalse(ItemSchedule.isPublished(it, now: today(), calendar: utc))
    }

    // MARK: 3) 짝 비교 — 시각만 붙였을 때 날 단위 판정은 동일, 알림 시각만 다르다 (핵심 그물)

    func testPair_identicalExceptNotificationHour() {
        let cal = utc, now = today()
        let bare = "2026-08-05", timed = "2026-08-05T19:00"

        // (a) D-day 동일
        XCTAssertEqual(DDayCalc.compute(day: bare, now: now, calendar: cal)!.days,
                       DDayCalc.compute(day: timed, now: now, calendar: cal)!.days)

        // (b) 게시 판정 동일 (마감만 있는 항목)
        XCTAssertEqual(ItemSchedule.isPublished(item("x", due: bare), now: now, calendar: cal),
                       ItemSchedule.isPublished(item("x", due: timed), now: now, calendar: cal))

        // (c) 규칙1(상한·위반) 동일
        XCTAssertEqual(ItemSchedule.resurfaceUpperBound(due: bare, now: now, calendar: cal),
                       ItemSchedule.resurfaceUpperBound(due: timed, now: now, calendar: cal))
        XCTAssertEqual(ItemSchedule.violatesRule1(resurface: "2026-08-05", due: bare, now: now, calendar: cal),
                       ItemSchedule.violatesRule1(resurface: "2026-08-05", due: timed, now: now, calendar: cal))

        // (d) 정렬 동일 — 같은 마감의 두 항목은 시각 유무와 무관하게 같은 순번(id tiebreak만)
        let secBare  = InboxSectionizer.split([item("A", due: bare),  item("B", due: bare)],  now: now, calendar: cal)
        let secTimed = InboxSectionizer.split([item("A", due: timed), item("B", due: timed)], now: now, calendar: cal)
        XCTAssertEqual(secBare.upcoming.map { $0.item.id }, secTimed.upcoming.map { $0.item.id })
        XCTAssertEqual(secBare.upcoming.first?.dday?.days, secTimed.upcoming.first?.dday?.days)

        // (e) 알림 발화 시각만 다르다 — date-only=9시, 시각 있으면 19시. 날짜는 같다.
        let planBare  = NotificationPlanner.plan(items: [item("A", resurface: bare)],  now: now, calendar: cal)
        let planTimed = NotificationPlanner.plan(items: [item("A", resurface: timed)], now: now, calendar: cal)
        XCTAssertEqual(cal.component(.hour, from: planBare.first!.fireDate), 9)
        XCTAssertEqual(cal.component(.hour, from: planTimed.first!.fireDate), 19)
        XCTAssertEqual(cal.startOfDay(for: planBare.first!.fireDate),
                       cal.startOfDay(for: planTimed.first!.fireDate))   // 같은 날 발화
    }

    // MARK: 4) 옛 값 동일 — date-only 판정이 지금과 동일 (회귀 감지선)

    func testOldValue_unchanged() {
        let cal = utc, now = today()
        let it = item("O", due: "2026-08-05", resurface: "2026-08-01")
        XCTAssertEqual(DDayCalc.compute(day: ItemSchedule.deadlineDay(it)!, now: now, calendar: cal)!.days, 3)
        XCTAssertTrue(ItemSchedule.isPublished(it, now: now, calendar: cal))   // resurface 08-01 지남 → 게시
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: cal)
        // publishDay = resurface(08-01)이 과거라 알림 없음(미래만) — 기존 동작 그대로
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: Stage 2 — 직렬화·시각 보존·보조 캡션

    private func at(_ h: Int, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: h, minute: min))!
    }

    func testDayTimeString_roundTrip() {
        let cal = utc
        let d = cal.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 19, minute: 30))!
        XCTAssertEqual(ItemSchedule.dayTimeString(d, calendar: cal), "2026-08-05T19:30")
        XCTAssertEqual(ItemSchedule.parseDay("2026-08-05T19:30", calendar: cal), d)   // 왕복(분 정밀)
    }

    func testWithTimeOfDay_preservesAndStripsAppropriately() {
        // 시각 있는 원본 → 새 날짜에 그 시각 유지
        XCTAssertEqual(ItemSchedule.withTimeOfDay("2026-08-12", from: "2026-08-05T08:00"), "2026-08-12T08:00")
        // 시각 없는 원본 → 날짜만
        XCTAssertEqual(ItemSchedule.withTimeOfDay("2026-08-12", from: "2026-08-05"), "2026-08-12")
        // 대상에 시각이 붙어 있어도 날짜부만 base로
        XCTAssertEqual(ItemSchedule.withTimeOfDay("2026-08-12T23:59", from: "2026-08-05T08:00"), "2026-08-12T08:00")
        XCTAssertNil(ItemSchedule.withTimeOfDay("2026-08-12", from: nil).firstIndex(of: "T"))  // nil 원본 → 날짜만
    }

    func testDefer_preservesTimeOfDay() {
        // 마감 없음 → 오늘(08-02)+7 = 08-09, 원래 미리 알림 시각 08:00 보존
        guard case let .deferred(day, _) = ItemSchedule.deferSevenDays(due: nil, now: today(), calendar: utc) else {
            return XCTFail("deferred 예상")
        }
        let kept = ItemSchedule.withTimeOfDay(day, from: "2026-07-01T08:00")
        XCTAssertEqual(kept, "2026-08-09T08:00")
        XCTAssertEqual(ItemSchedule.timeOfDay(kept)?.hour, 8)
    }

    func testWithinDayCaption_todayWithTime() {
        let cal = utc
        XCTAssertEqual(ItemSchedule.withinDayCaption("2026-08-02T19:00", now: at(16), calendar: cal), "3시간 남음")
        XCTAssertEqual(ItemSchedule.withinDayCaption("2026-08-02T19:00", now: at(20), calendar: cal), "지남")
        XCTAssertNil(ItemSchedule.withinDayCaption("2026-08-03T19:00", now: at(16), calendar: cal))   // 다른 날 → nil
        XCTAssertNil(ItemSchedule.withinDayCaption("2026-08-02", now: at(16), calendar: cal))         // 시각 없음 → nil
    }
}
