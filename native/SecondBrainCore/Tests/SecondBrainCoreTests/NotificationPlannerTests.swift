import XCTest
@testable import SecondBrainCore

final class NotificationPlannerTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func item(_ id: String, due: String? = nil, resurface: String? = nil) -> ResolvedItem {
        var f: [String: String] = ["raw": "\(id) 내용"]
        if let due { f["due"] = due }
        if let resurface { f["resurface"] = resurface }
        return ResolvedItem(id: id, fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }

    func testPlansFutureOnly_resurfacePreferred_sorted() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 0))!
        let items = [
            item("A", due: "2026-07-19"),                       // 미래 due
            item("B", resurface: "2026-07-18"),                 // 미래 resurface(우선)
            item("C", due: "2026-07-14"),                       // 과거 → 제외
            item("D", due: "none"),                             // 시점 없음 → 제외
            item("E", due: "none", resurface: "weekly"),        // 둘 다 날짜 아님 → 제외
            item("F", due: "2026-07-30", resurface: "2026-07-18"), // 둘 다 있음 → **두 건**(5-A 정정)
        ]
        let plan = NotificationPlanner.plan(items: items, now: now, calendar: cal, hour: 9)

        // **정정(Stage 5-A, 2026-08-04).** 옛 기대는 `["B", "F", "A"]`(항목당 1건, resurface 우선)였다.
        // 지금은 F가 미리 알림·마감 **두 지점**을 내므로 07-30에 F가 한 번 더 온다.
        // 동일 시각(07-18)의 B·F 순서는 id tiebreak로 **결정적**이다(옛 주석의 "안정"은 보장이 아니었다).
        XCTAssertEqual(plan.map { $0.id }, ["B", "F", "A", "F"])   // 07-18, 07-18, 07-19, 07-30
        XCTAssertEqual(plan.map { $0.kind }, [.lead, .lead, .due, .due])
        // 시각 = 해당 날 09:00 UTC
        let fB = cal.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 9))!
        XCTAssertEqual(plan.first?.fireDate, fB)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > now })    // 전부 미래
        XCTAssertEqual(plan.first?.body, "B 내용")
    }

    /// **정정(Stage 5-B, 2026-08-04).** 옛 기대는 단일 상한 32(`limit: 32`)였다. 지금은 **몫이 갈려서**
    /// 일반 항목 50개는 **일반 몫(24)** 까지만 등록되고 나머지는 잘린다 — 그리고 **잘린 개수가 값으로 나온다.**
    func testPlainItemsCapAtPlainShare_andDropsAreCounted() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 0))!
        let items = (1...50).map { item("x\($0)", due: "2026-08-01") }
        let r = NotificationPlanner.planned(items: items, now: now, calendar: cal, hour: 9)
        XCTAssertEqual(r.scheduled.count, 24)
        XCTAssertEqual(r.usedPlain, 24)
        XCTAssertEqual(r.usedRecurring, 0)
        XCTAssertEqual(r.droppedPlainCycles, 26)     // 50 − 24 (각 1슬롯)
        XCTAssertEqual(r.droppedSlots, 26)
        XCTAssertTrue(r.summary.contains("잘림"))     // 확인 경로가 실제로 알려준다
    }

    func testEmptyWhenNoDates() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 0))!
        let plan = NotificationPlanner.plan(items: [item("A", due: "none"), item("B")],
                                            now: now, calendar: cal, hour: 9)
        XCTAssertTrue(plan.isEmpty)
    }

    /// **정정(Stage 5-A, 2026-08-04).** 옛 이름은 `testFiresOnPublishDay_notDeadline_unchanged`였고
    /// "알림은 미리 알림에만 울린다(마감엔 안 울린다)"를 **불변으로 못박고 있었다** — 그 단정이 곧
    /// **lead-time 구멍**이었다(7시 미리 알림 + 8시 약이 7시만 울리고 8시엔 조용). 이제 **두 지점 다** 울린다.
    /// 옛 기대는 지우지 않고 여기 남긴다: 마감 07-30 + 미리 알림 07-18 → 옛날 `[07-18]`, 지금 `[07-18, 07-30]`.
    func testFiresOnBothLeadAndDue_theLeadTimeHoleClosed() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 0))!
        let plan = NotificationPlanner.plan(items: [item("A", due: "2026-07-30", resurface: "2026-07-18")],
                                            now: now, calendar: cal, hour: 9)
        let lead = cal.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 9))!
        let due  = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 9))!
        XCTAssertEqual(plan.map { $0.fireDate }, [lead, due])          // 이른 순
        XCTAssertEqual(plan.map { $0.kind }, [.lead, .due])
        // 식별자가 갈린다 — 안 갈리면 두 번째 등록이 첫 번째를 덮어써 한 건만 남는다.
        XCTAssertEqual(plan.map { $0.requestKey }, ["A:lead", "A:due"])
        XCTAssertEqual(Set(plan.map { $0.requestKey }).count, 2)
    }

    /// **lead-time 그 자체** — 7시 미리 알림 + 8시 회차. 구멍이 있던 시절엔 7시만 울렸다.
    func testLeadTime_sameDayTwoInstants() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 0))!
        let plan = NotificationPlanner.plan(
            items: [item("약", due: "2026-08-05T08:00", resurface: "2026-08-05T07:00")],
            now: now, calendar: cal)
        XCTAssertEqual(plan.map { $0.kind }, [.lead, .due])
        XCTAssertEqual(plan.map { $0.fireDate }, [
            cal.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 7))!,
            cal.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 8))!,
        ])
    }

    // MARK: lead 0 접힘 — 이유 없이 예산을 2배로 쓰지 않는다

    func testLeadZero_collapsesToSingleDuePoint() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 0))!
        // 미리 알림 == 마감(같은 시각) → 한 건, 그것도 회차(.due)로.
        let same = NotificationPlanner.plan(
            items: [item("A", due: "2026-08-05T08:00", resurface: "2026-08-05T08:00")],
            now: now, calendar: cal)
        XCTAssertEqual(same.map { $0.kind }, [.due])
        // 날짜만 + 같은 날 → 둘 다 9시 폴백으로 같은 순간이 되므로 역시 한 건.
        let bareSameDay = NotificationPlanner.plan(items: [item("B", due: "2026-08-05", resurface: "2026-08-05")],
                                                  now: now, calendar: cal, hour: 9)
        XCTAssertEqual(bareSameDay.map { $0.kind }, [.due])
    }

    func testSinglePoint_whenOnlyOneSideExists() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 0))!
        XCTAssertEqual(NotificationPlanner.plan(items: [item("A", due: "2026-08-05T08:00")],
                                               now: now, calendar: cal).map { $0.kind }, [.due])
        XCTAssertEqual(NotificationPlanner.plan(items: [item("B", resurface: "2026-08-05T07:00")],
                                               now: now, calendar: cal).map { $0.kind }, [.lead])
    }

    /// 지난 lead는 빠지고 미래 마감만 남는다 — 지점별로 따로 판정한다(둘 다 미래일 필요 없음).
    func testPastLeadDropped_futureDueKept() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 12))!
        let plan = NotificationPlanner.plan(
            items: [item("A", due: "2026-08-05T08:00", resurface: "2026-08-04T07:00")],   // lead 이미 지남
            now: now, calendar: cal)
        XCTAssertEqual(plan.map { $0.kind }, [.due])
    }

    // MARK: 알려주는 알림(자동 완성 있는 되풀이) — 한 건만

    private func recur(_ id: String, due: String, resurface: String? = nil, auto: String) -> ResolvedItem {
        var f: [String: String] = ["type": "recurrence", "recur": "yearly", "due": due, "raw": "어머니 생신"]
        if let resurface { f["resurface"] = resurface }
        f["recurAuto"] = auto
        return ResolvedItem(id: id, fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }

    func testNotifyOnly_autoCompleteRecurrence_onePointOnly() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 0))!
        // lead가 있으면 lead 하나만 — 미리 알아야 쓸모가 있다(선물·연락).
        let withLead = NotificationPlanner.plan(
            items: [recur("생신", due: "2026-08-20T09:00", resurface: "2026-08-17T09:00", auto: "endOfDay")],
            now: now, calendar: cal)
        XCTAssertEqual(withLead.map { $0.kind }, [.lead])
        XCTAssertEqual(withLead.first?.requestKey, "생신:lead")
        // lead가 없으면 회차 하나.
        let noLead = NotificationPlanner.plan(items: [recur("생신2", due: "2026-08-20T09:00", auto: "noon")],
                                              now: now, calendar: cal)
        XCTAssertEqual(noLead.map { $0.kind }, [.due])
        // 자동 완성이 없으면(약) 완료를 요구하므로 두 건.
        let med = NotificationPlanner.plan(
            items: [recur("약", due: "2026-08-20T08:00", resurface: "2026-08-20T07:00", auto: "none")],
            now: now, calendar: cal)
        XCTAssertEqual(med.map { $0.kind }, [.lead, .due])
    }

    // MARK: 회귀선

    /// 두 건 발행은 **되풀이 특례가 아니다** — 일반 항목도 받는다(두 칸 역할 분리의 귀결).
    func testTwoPoints_appliesToPlainItemsToo() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 0))!
        let plan = NotificationPlanner.plan(
            items: [item("보고서", due: "2026-08-10T18:00", resurface: "2026-08-07T09:00")],
            now: now, calendar: cal)
        XCTAssertEqual(plan.map { $0.kind }, [.lead, .due])
    }

    /// **분류 게이트를 상속한다** — 그 분류가 안 쓰는 칸은 지점이 아니다.
    /// 주차(parking)는 미리 알림은 쓰고 마감은 안 쓴다 → 마감 지점이 안 나온다.
    func testClassGateInherited_dueSuppressedForParking() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 0))!
        var f: [String: String] = ["type": "parking", "due": "2026-08-31", "resurface": "2026-08-06", "raw": "주차"]
        f["raw"] = "주차 항목"
        let it = ResolvedItem(id: "P", fields: f, deleted: false, confirmed: false,
                              createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: cal)
        XCTAssertEqual(plan.map { $0.kind }, [.lead])
    }

    /// 정렬은 (시각, id, 종류)로 **완전 결정적** — 상한에 걸릴 때 무엇이 남는지가 흔들리지 않게.
    func testSortIsFullyDeterministic() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 0))!
        let items = [item("B", due: "2026-08-05T09:00"),
                     item("A", due: "2026-08-05T09:00"),
                     item("C", due: "2026-08-05T08:00")]
        let plan = NotificationPlanner.plan(items: items, now: now, calendar: cal)
        XCTAssertEqual(plan.map { $0.id }, ["C", "A", "B"])   // 08:00 → 09:00(A,B는 id 순)
    }

    /// 꺼둔 되풀이는 두 지점 다 안 낸다(2026-08-03 가드 회귀선).
    func testDormantRecurrence_emitsNothing() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 0))!
        var f: [String: String] = ["type": "recurrence", "recur": "daily", "raw": "약",
                                   "due": "2026-08-05T08:00", "resurface": "2026-08-05T07:00"]
        f["recurPaused"] = "true"
        let it = ResolvedItem(id: "off", fields: f, deleted: false, confirmed: false,
                              createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
        XCTAssertTrue(NotificationPlanner.plan(items: [it], now: now, calendar: cal).isEmpty)
    }
}
