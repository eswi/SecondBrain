import XCTest
@testable import SecondBrainCore

/// §7 (c) Stage D3-B — **분류 게이트**: 그 분류가 안 쓰는 칸의 날짜는 시점이 아니다.
/// 게이트는 `ItemSchedule.effectiveDay` 한 곳에 있고, 소비자(알림·"곧 닥칠 것")가 상속한다.
/// 칸별 판단이 핵심: 주차는 다시 보기는 쓰고 **마감만** 안 쓴다.
final class ClassGateTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func item(_ id: String, type: String? = nil, due: String? = nil, resurface: String? = nil,
                      created: Int64 = 1) -> ResolvedItem {
        var f: [String: String] = ["raw": "\(id) 내용"]
        if let type { f["type"] = type }
        if let due { f["due"] = due }
        if let resurface { f["resurface"] = resurface }
        return ResolvedItem(id: id, fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: created, counter: 0, deviceId: "t"))
    }

    // MARK: 시간을 안 쓰는 분류 (noTime = 정보·아이디어·원칙)

    /// 1. 아이디어는 마감을 안 쓴다 → 옛 실날짜가 남아 있어도 시점 없음.
    func testGate_idea_dueRealDate_isNoTime() {
        XCTAssertNil(ItemSchedule.effectiveDay(item("I", type: "idea", due: "2026-07-20")))
        XCTAssertNil(ItemSchedule.effectiveDay(item("I2", type: "idea", resurface: "2026-07-20")))
        XCTAssertNil(ItemSchedule.effectiveDay(item("I3", type: "info", due: "2026-07-20")))
        XCTAssertNil(ItemSchedule.effectiveDay(item("I4", type: "principle", due: "2026-07-20")))
    }

    /// 2. 할일은 마감을 쓴다 → 그대로 그 날짜(회귀 가드).
    func testGate_infoAction_dueRealDate_kept() {
        XCTAssertEqual(ItemSchedule.effectiveDay(item("A", type: "info-action", due: "2026-07-20")), "2026-07-20")
        // resurface 우선순위도 그대로
        XCTAssertEqual(ItemSchedule.effectiveDay(item("A2", type: "info-action",
                                                      due: "2026-07-30", resurface: "2026-07-18")), "2026-07-18")
        XCTAssertEqual(ItemSchedule.effectiveDay(item("A3", type: "promise", due: "2026-07-20")), "2026-07-20")
        XCTAssertEqual(ItemSchedule.effectiveDay(item("A4", type: "event", due: "2026-07-20")), "2026-07-20")
    }

    // MARK: 정의 없는 분류 = 전부 씀 (폴백은 ClassSpecCatalog.uses 한 곳)

    /// 3. 미분류(type 없음/빈 문자열)의 날짜는 살아 있어야 한다 — 분류가 안 붙었다고 조용히 사라지면 안 됨.
    func testFallback_unclassified_usesEverything() {
        XCTAssertTrue(ClassSpecCatalog.uses(nil, .due))
        XCTAssertTrue(ClassSpecCatalog.uses(nil, .resurface))
        XCTAssertTrue(ClassSpecCatalog.uses("", .due))          // 미분류 되돌리기가 남기는 빈 값
        XCTAssertEqual(ItemSchedule.effectiveDay(item("U", due: "2026-07-20")), "2026-07-20")
        XCTAssertEqual(ItemSchedule.effectiveDay(item("U2", type: "", due: "2026-07-20")), "2026-07-20")
    }

    /// 4. 미등록 key(`discard`·오타·미래의 새 값)도 전부 씀 — 표에 없다고 날짜를 지우지 않는다.
    func testFallback_unregisteredKey_usesEverything() {
        XCTAssertTrue(ClassSpecCatalog.uses("discard", .due))
        XCTAssertTrue(ClassSpecCatalog.uses("주차", .due))       // key는 "parking" — 한글 값은 미등록
        XCTAssertEqual(ItemSchedule.effectiveDay(item("D", type: "discard", due: "2026-07-20")), "2026-07-20")
        XCTAssertEqual(ItemSchedule.effectiveDay(item("D2", type: "주차", due: "2026-07-20")), "2026-07-20")
    }

    // MARK: 칸별 판단 (주차 = 마감만 안 씀)

    /// 5. 주차는 마감을 안 쓴다 → 마감 실날짜만 있으면 시점 없음.
    func testGate_parking_dueRealDate_isNoTime() {
        XCTAssertFalse(ClassSpecCatalog.uses("parking", .due))
        XCTAssertNil(ItemSchedule.effectiveDay(item("P", type: "parking", due: "2026-07-20")))
    }

    /// 6. 주차는 다시 보기는 쓴다 → 그 날짜가 살아야 한다("시간 안 쓰는 분류면 통째로 nil"이 아님).
    func testGate_parking_resurfaceRealDate_kept() {
        XCTAssertTrue(ClassSpecCatalog.uses("parking", .resurface))
        XCTAssertEqual(ItemSchedule.effectiveDay(item("P2", type: "parking", resurface: "2026-07-20")), "2026-07-20")
        // 마감은 막고 다시 보기만 통과 (둘 다 실날짜여도 due로 새지 않는다)
        XCTAssertEqual(ItemSchedule.effectiveDay(item("P3", type: "parking",
                                                      due: "2026-07-30", resurface: "2026-07-18")), "2026-07-18")
    }

    // MARK: 소비자 상속 — 게이트된 항목은 '사라지는' 게 아니라 시점 없는 쪽으로 옮겨간다

    /// 게이트 걸린 아이디어는 "곧 닥칠 것"에서 빠지되 **"최근 들어온 것"에 그대로 있다**(유실이면 버그).
    /// 알림 쪽은 계획에서만 빠진다(항목·데이터는 그대로).
    func testConsumers_gatedItemMovesToRecent_notLost() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 10))!
        let idea = item("I", type: "idea", due: "2026-07-20")
        let unclassified = item("U", due: "2026-07-20")
        let s = InboxSectionizer.split([idea, unclassified], now: now, calendar: cal)
        XCTAssertEqual(s.upcoming.map { $0.item.id }, ["U"])     // 미분류는 남고
        XCTAssertEqual(s.recent.map { $0.id }, ["I"])            // 아이디어는 이동(유실 아님)
        XCTAssertEqual(s.upcoming.count + s.recent.count, 2)     // 총 개수 보존
        XCTAssertEqual(NotificationPlanner.plan(items: [idea, unclassified], now: now, calendar: cal).map { $0.id },
                       ["U"])                                     // 알림 계획에서도 아이디어만 빠짐
    }
}
