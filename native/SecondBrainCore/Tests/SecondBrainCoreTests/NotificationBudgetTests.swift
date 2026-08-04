import XCTest
@testable import SecondBrainCore

/// **Stage 5-B (2026-08-04) — 예산 분리·라운드로빈·단방향 대여·잘림 가시성.**
///
/// 목적은 정확한 숫자가 아니라 **"반복이 일반을 조용히 밀어내지 않는다"**.
/// 옛 모델은 `fireDate` 하나로 정렬해 앞에서 잘랐고, 반복은 다음 발화가 늘 임박해 정렬 최상위를
/// 점거했다 → 먼 마감의 일반 항목이 조용히 밀려났다. 그 양상을 여기서 못박는다.
final class NotificationBudgetTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(
        timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 8, day: 4, hour: 0))!

    /// 되풀이 — 매일, 자동완성 없음(약). lead 주면 회차당 2슬롯.
    private func med(_ id: String, due: String, resurface: String? = nil) -> ResolvedItem {
        var f: [String: String] = ["type": "recurrence", "recur": "daily", "due": due, "raw": "약 \(id)"]
        if let resurface { f["resurface"] = resurface }
        return ResolvedItem(id: id, fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }
    /// 일반 항목 — 마감만(1슬롯) 또는 lead까지(2슬롯).
    private func task(_ id: String, due: String, resurface: String? = nil) -> ResolvedItem {
        var f: [String: String] = ["type": "task", "due": due, "raw": "일 \(id)"]
        if let resurface { f["resurface"] = resurface }
        return ResolvedItem(id: id, fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }

    // MARK: 몫이 갈린다 — 이게 5-B의 본체

    /// **반복이 아무리 많아도 일반 몫은 보장된다.** 옛 모델이라면 임박한 반복이 먼 일반을 다 밀어냈다.
    func testRecurringCannotStarvePlain() {
        // 반복 20개(각 lead+회차 = 2슬롯 = 40슬롯 요구, 임박) + 일반 10개(먼 마감).
        let recurs = (1...20).map { med("r\($0)", due: "2026-08-05T08:00", resurface: "2026-08-05T07:00") }
        let plains = (1...10).map { task("p\($0)", due: "2026-12-01T09:00") }
        let r = NotificationPlanner.planned(items: recurs + plains, now: now, calendar: utc)

        XCTAssertEqual(r.usedPlain, 10)                                   // 일반 10건 전부 들어갔다
        XCTAssertEqual(Set(r.scheduled.filter { $0.id.hasPrefix("p") }.map { $0.id }).count, 10)
        XCTAssertLessThanOrEqual(r.usedRecurring, 24 + (24 - 10))         // 반복은 자기 몫 + 남은 대여까지만
        XCTAssertGreaterThan(r.droppedRecurringCycles, 0)                 // 넘친 반복은 잘리고
        XCTAssertEqual(r.droppedPlainCycles, 0)                           // 일반은 하나도 안 잘렸다
    }

    /// 총량은 마진 안에 있다 — iOS 64에 안 닿는다.
    func testTotalNeverExceedsBudget() {
        let recurs = (1...40).map { med("r\($0)", due: "2026-08-05T08:00", resurface: "2026-08-05T07:00") }
        let plains = (1...40).map { task("p\($0)", due: "2026-08-06T09:00") }
        let r = NotificationPlanner.planned(items: recurs + plains, now: now, calendar: utc)
        XCTAssertLessThanOrEqual(r.scheduled.count, NotificationBudget.standard.total)
        XCTAssertEqual(r.scheduled.count, r.used)
    }

    // MARK: 회차 묶음은 쪼개지 않는다 — 5-A 구멍의 재발 방지

    /// **lead만 오고 회차가 안 오는 일은 없다.** 예산이 홀수로 남아도 묶음을 쪼개지 않는다.
    /// 쪼개면 "곧"만 울리고 "지금"이 안 울려서 5-A에서 닫은 구멍이 예산 때문에 조용히 다시 열린다.
    func testBundleIsAtomic_neverLeadWithoutDue() {
        // 반복 몫 3 → 2슬롯 묶음 하나만 들어가고 남은 1칸엔 아무것도 안 넣는다.
        // (일반 몫을 0으로 둬야 대여가 안 생겨 홀수 잔여가 실제로 만들어진다.)
        let budget = NotificationBudget(total: 3, recurring: 3, plain: 0)
        let recurs = [med("a", due: "2026-08-05T08:00", resurface: "2026-08-05T07:00"),
                      med("b", due: "2026-08-06T08:00", resurface: "2026-08-06T07:00")]
        let r = NotificationPlanner.planned(items: recurs, now: now, calendar: utc, budget: budget)

        XCTAssertEqual(r.usedRecurring, 2)                 // 3칸 중 2칸만 — 쪼개서 3칸 채우지 않는다
        XCTAssertEqual(r.droppedRecurringCycles, 1)
        // 등록된 항목은 반드시 lead·회차 **둘 다** 가진다.
        for id in Set(r.scheduled.map { $0.id }) {
            let kinds = Set(r.scheduled.filter { $0.id == id }.map { $0.kind })
            XCTAssertEqual(kinds, [.lead, .due], "\(id)가 반쪽만 등록됐다")
        }
    }

    // MARK: 라운드로빈 — 어떤 항목도 0회차가 되지 않게

    /// 이른 순으로만 채우면 임박한 항목이 몫을 점거한다. 라운드로빈은 **항목마다 한 회차씩** 준다.
    /// (5-B는 항목당 1묶음이므로, 라운드 안 정렬이 이른 순 + id로 결정적인지를 본다.)
    func testRoundOrderIsDeterministic_earliestThenId() {
        let budget = NotificationBudget(total: 4, recurring: 2, plain: 2)
        let items = [task("b", due: "2026-08-05T09:00"),
                     task("a", due: "2026-08-05T09:00"),   // 같은 시각 → id 순으로 a가 먼저
                     task("c", due: "2026-08-06T09:00")]   // 더 늦음 → 밀린다
        let r = NotificationPlanner.planned(items: items, now: now, calendar: utc, budget: budget)
        XCTAssertEqual(r.scheduled.map { $0.id }, ["a", "b"])
        XCTAssertEqual(r.droppedPlainCycles, 1)
    }

    // MARK: 단방향 대여

    /// 일반이 몫을 남기면 반복이 빌린다 — 호라이즌(5-C)이 그만큼 늘어난다.
    func testRecurringBorrowsPlainLeftover() {
        let budget = NotificationBudget(total: 8, recurring: 4, plain: 4)
        // 일반 1개(1슬롯) → 3칸 남김. 반복은 4 + 3 = 7칸까지 쓸 수 있다(2슬롯 묶음 3개 = 6).
        let items = [task("p", due: "2026-08-20T09:00")]
            + (5...9).map { med("r\($0)", due: "2026-08-0\($0)T08:00", resurface: "2026-08-0\($0)T07:00") }
        let r = NotificationPlanner.planned(items: items, now: now, calendar: utc, budget: budget)
        XCTAssertEqual(r.usedPlain, 1)
        XCTAssertEqual(r.usedRecurring, 6)               // 4(자기 몫) + 2(대여) — 묶음 단위라 7칸엔 6만 들어간다
        XCTAssertEqual(r.borrowedFromPlain, 2)
        XCTAssertLessThanOrEqual(r.used, budget.total)
    }

    /// **반대 방향은 없다(단방향).** 반복이 몫을 남겨도 일반은 자기 몫을 넘지 않는다.
    /// 반복 수요는 체인으로 무한히 늘 수 있고(5-C) 일반 수요는 유한해서, 보장해야 할 쪽은 일반의 하한이다.
    /// **미결:** 일반이 자기 몫에 실제로 닿는 날이 오면 양방향(하한 보장 + 남는 몫 상호 대여)을 재검토할 것.
    func testPlainDoesNotBorrowFromRecurring() {
        let budget = NotificationBudget(total: 8, recurring: 4, plain: 4)
        let items = (5...9).map { task("p\($0)", due: "2026-08-0\($0)T09:00") }   // 5슬롯 요구(전부 미래)
        let r = NotificationPlanner.planned(items: items, now: now, calendar: utc, budget: budget)
        XCTAssertEqual(r.usedPlain, 4)                   // 반복이 4칸을 안 쓰지만 일반은 4에서 멈춘다
        XCTAssertEqual(r.droppedPlainCycles, 1)
    }

    // MARK: 잘림 가시성 — 알림은 "안 오는 것"을 눈치채기 어렵다

    func testDropsAreVisibleInSummary() {
        let budget = NotificationBudget(total: 2, recurring: 1, plain: 1)
        let items = [task("p1", due: "2026-08-05T09:00"), task("p2", due: "2026-08-06T09:00"),
                     med("r1", due: "2026-08-05T08:00", resurface: "2026-08-05T07:00")]
        let r = NotificationPlanner.planned(items: items, now: now, calendar: utc, budget: budget)
        XCTAssertEqual(r.droppedPlainCycles, 1)
        XCTAssertEqual(r.droppedRecurringCycles, 1)      // 2슬롯 묶음이 1칸에 안 들어간다
        XCTAssertEqual(r.droppedCycles, 2)
        XCTAssertEqual(r.droppedSlots, 3)                // 일반 1 + 반복 2
        XCTAssertTrue(r.summary.contains("⚠️잘림"), r.summary)
    }

    /// 아무것도 안 잘리면 경고가 안 뜬다(잡음 방지).
    func testSummaryQuietWhenNothingDropped() {
        let r = NotificationPlanner.planned(items: [task("p", due: "2026-08-05T09:00")],
                                          now: now, calendar: utc)
        XCTAssertEqual(r.droppedCycles, 0)
        XCTAssertFalse(r.summary.contains("잘림"), r.summary)
        XCTAssertTrue(r.summary.contains("알림 1건"), r.summary)
    }

    /// 꺼둔 되풀이는 예산을 **먹지도 않는다**(잘림으로도 안 센다 — 애초에 낼 게 없다).
    func testDormantConsumesNoBudget() {
        var f: [String: String] = ["type": "recurrence", "recur": "daily", "raw": "약",
                                   "due": "2026-08-05T08:00", "recurPaused": "true"]
        f["resurface"] = "2026-08-05T07:00"
        let off = ResolvedItem(id: "off", fields: f, deleted: false, confirmed: false,
                               createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
        let r = NotificationPlanner.planned(items: [off], now: now, calendar: utc)
        XCTAssertEqual(r.used, 0)
        XCTAssertEqual(r.droppedCycles, 0)
    }
}
