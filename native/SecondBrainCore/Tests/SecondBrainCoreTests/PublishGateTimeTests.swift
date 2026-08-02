import XCTest
@testable import SecondBrainCore

/// #3 (2026-08-03) — **게시 게이트가 시각까지 본다.** `isPublished`: 미리 알림 시점이 오면(지났으면) 게시.
/// 핵심 불변식(사용자 명시): **시각이 지난 항목은 계속 보인다**(놓친 것을 숨기지 않는다).
/// date-only 항목은 자정부터 = 동작 변화 없음.
final class PublishGateTimeTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func at(_ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
    }
    private func item(resurface: String) -> ResolvedItem {
        ResolvedItem(id: "a", fields: ["raw": "약", "resurface": resurface], deleted: false, confirmed: false,
                     createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }
    private func pub(_ r: String, _ now: Date) -> Bool { ItemSchedule.isPublished(item(resurface: r), now: now, calendar: utc) }

    // ★★ 시각이 지난 항목은 계속 보인다 — 아침 8시 약을 오후에·다음날에 열어도 목록에 있어야.
    func testResurfaceTimePassed_staysPublished() {
        XCTAssertTrue(pub("2026-08-02T08:00", at(8, 2, 14)), "같은 날 오후 — 계속 보임")
        XCTAssertTrue(pub("2026-08-02T08:00", at(8, 3, 9)),  "다음날 — 놓친 채 계속 보임")
        XCTAssertTrue(pub("2026-08-02T08:00", at(8, 2, 8)),  "정각 — 게시 시작")
    }

    // 시각이 미래면 그 시각 전까지 안 보인다(도래 전엔 묻어둔다).
    func testResurfaceTimeFuture_hiddenUntilTime() {
        XCTAssertFalse(pub("2026-08-02T20:00", at(8, 2, 14)), "20시 전 — 아직")
        XCTAssertTrue(pub("2026-08-02T20:00", at(8, 2, 21)),  "20시 후 — 게시")
        // 같은 날 자정 직후(옛 날짜 게이트라면 보였을 것) — 이제 안 보임
        XCTAssertFalse(pub("2026-08-02T20:00", at(8, 2, 0, 1)))
    }

    // date-only는 자정부터 = 동작 변화 없음(시각 없는 항목 불변).
    func testDateOnly_unchanged() {
        XCTAssertTrue(pub("2026-08-02", at(8, 2, 0, 0)),  "오늘 자정부터 보임")
        XCTAssertTrue(pub("2026-08-02", at(8, 2, 23)),    "오늘 종일 보임")
        XCTAssertFalse(pub("2026-08-03", at(8, 2, 23)),   "미래 날 — 안 보임")
        XCTAssertTrue(pub("2026-08-01", at(8, 2, 0)),     "지난 날 — 계속 보임")
    }
}
