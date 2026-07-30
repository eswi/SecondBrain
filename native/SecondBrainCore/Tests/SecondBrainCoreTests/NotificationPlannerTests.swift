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
            item("F", due: "2026-07-30", resurface: "2026-07-18"), // resurface 우선
        ]
        let plan = NotificationPlanner.plan(items: items, now: now, calendar: cal, hour: 9)

        XCTAssertEqual(plan.map { $0.id }, ["B", "F", "A"])      // 07-18, 07-18, 07-19 (이른 순; B·F 동일자 → 안정)
        // 시각 = 해당 날 09:00 UTC
        let fB = cal.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 9))!
        XCTAssertEqual(plan.first?.fireDate, fB)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > now })    // 전부 미래
        XCTAssertEqual(plan.first?.body, "B 내용")
    }

    func testLimitCap() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 0))!
        let items = (1...50).map { item("x\($0)", due: "2026-08-01") }
        let plan = NotificationPlanner.plan(items: items, now: now, calendar: cal, hour: 9, limit: 32)
        XCTAssertEqual(plan.count, 32)
    }

    func testEmptyWhenNoDates() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 0))!
        let plan = NotificationPlanner.plan(items: [item("A", due: "none"), item("B")],
                                            now: now, calendar: cal, hour: 9)
        XCTAssertTrue(plan.isEmpty)
    }

    /// 알림은 **게시 시작일**(publishDay = 미리 알림 우선)에 울린다 — 역할 분리(Stage 1) 후에도 불변.
    /// 마감을 별도 기준으로 쓰는 건 배지·정렬뿐, 알림 시점은 그대로여야 한다(동작 변화 0).
    func testFiresOnPublishDay_notDeadline_unchanged() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 0))!
        // 마감 07-30, 미리 알림 07-18 → 알림은 마감이 아니라 미리 알림(07-18)에 울려야 한다.
        let plan = NotificationPlanner.plan(items: [item("A", due: "2026-07-30", resurface: "2026-07-18")],
                                            now: now, calendar: cal, hour: 9)
        let fire = cal.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 9))!
        XCTAssertEqual(plan.map { $0.fireDate }, [fire])
    }
}
