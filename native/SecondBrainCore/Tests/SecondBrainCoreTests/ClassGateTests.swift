import XCTest
@testable import SecondBrainCore

/// §7 (c) Stage D3-B — **분류 게이트**: 그 분류가 안 쓰는 칸의 날짜는 시점이 아니다.
/// 게이트는 `ItemSchedule.publishDay` 한 곳에 있고, 소비자(알림·"곧 닥칠 것")가 상속한다.
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
        XCTAssertNil(ItemSchedule.publishDay(item("I", type: "idea", due: "2026-07-20")))
        XCTAssertNil(ItemSchedule.publishDay(item("I2", type: "idea", resurface: "2026-07-20")))
        XCTAssertNil(ItemSchedule.publishDay(item("I3", type: "info", due: "2026-07-20")))
        XCTAssertNil(ItemSchedule.publishDay(item("I4", type: "principle", due: "2026-07-20")))
    }

    /// 2. 할일은 마감을 쓴다 → 그대로 그 날짜(회귀 가드).
    func testGate_infoAction_dueRealDate_kept() {
        XCTAssertEqual(ItemSchedule.publishDay(item("A", type: "info-action", due: "2026-07-20")), "2026-07-20")
        // resurface 우선순위도 그대로
        XCTAssertEqual(ItemSchedule.publishDay(item("A2", type: "info-action",
                                                      due: "2026-07-30", resurface: "2026-07-18")), "2026-07-18")
        XCTAssertEqual(ItemSchedule.publishDay(item("A3", type: "promise", due: "2026-07-20")), "2026-07-20")
        XCTAssertEqual(ItemSchedule.publishDay(item("A4", type: "event", due: "2026-07-20")), "2026-07-20")
    }

    // MARK: 정의 없는 분류 = 전부 씀 (폴백은 ClassSpecCatalog.uses 한 곳)

    /// 3. 미분류(type 없음/빈 문자열)의 날짜는 살아 있어야 한다 — 분류가 안 붙었다고 조용히 사라지면 안 됨.
    func testFallback_unclassified_usesEverything() {
        XCTAssertTrue(ClassSpecCatalog.uses(nil, .due))
        XCTAssertTrue(ClassSpecCatalog.uses(nil, .resurface))
        XCTAssertTrue(ClassSpecCatalog.uses("", .due))          // 미분류 되돌리기가 남기는 빈 값
        XCTAssertEqual(ItemSchedule.publishDay(item("U", due: "2026-07-20")), "2026-07-20")
        XCTAssertEqual(ItemSchedule.publishDay(item("U2", type: "", due: "2026-07-20")), "2026-07-20")
    }

    /// 4. 미등록 key(`discard`·오타·미래의 새 값)도 전부 씀 — 표에 없다고 날짜를 지우지 않는다.
    func testFallback_unregisteredKey_usesEverything() {
        XCTAssertTrue(ClassSpecCatalog.uses("discard", .due))
        XCTAssertTrue(ClassSpecCatalog.uses("주차", .due))       // key는 "parking" — 한글 값은 미등록
        XCTAssertEqual(ItemSchedule.publishDay(item("D", type: "discard", due: "2026-07-20")), "2026-07-20")
        XCTAssertEqual(ItemSchedule.publishDay(item("D2", type: "주차", due: "2026-07-20")), "2026-07-20")
    }

    // MARK: 칸별 판단 (주차 = 마감만 안 씀)

    /// 5. 주차는 마감을 안 쓴다 → 마감 실날짜만 있으면 시점 없음.
    func testGate_parking_dueRealDate_isNoTime() {
        XCTAssertFalse(ClassSpecCatalog.uses("parking", .due))
        XCTAssertNil(ItemSchedule.publishDay(item("P", type: "parking", due: "2026-07-20")))
    }

    /// 6. 주차는 다시 보기는 쓴다 → 그 날짜가 살아야 한다("시간 안 쓰는 분류면 통째로 nil"이 아님).
    func testGate_parking_resurfaceRealDate_kept() {
        XCTAssertTrue(ClassSpecCatalog.uses("parking", .resurface))
        XCTAssertEqual(ItemSchedule.publishDay(item("P2", type: "parking", resurface: "2026-07-20")), "2026-07-20")
        // 마감은 막고 다시 보기만 통과 (둘 다 실날짜여도 due로 새지 않는다)
        XCTAssertEqual(ItemSchedule.publishDay(item("P3", type: "parking",
                                                      due: "2026-07-30", resurface: "2026-07-18")), "2026-07-18")
    }

    // MARK: 캡션·목록 게이트 (검색·보관함 날짜 노출 — deadlineDay / gatedResurface)

    /// 캡션이 쓰는 두 게이트 함수: 안 쓰는 칸의 날짜는 노출 대상에서 빠진다(검색·보관함 캡션 회귀 가드).
    func testCaptionGate_dropsUnusedFields() {
        // 아이디어(둘 다 안 씀) — 실날짜가 남아 있어도 캡션에 안 나온다.
        XCTAssertNil(ItemSchedule.deadlineDay(item("I", type: "idea", due: "2026-07-20")))
        XCTAssertNil(ItemSchedule.gatedResurface(item("I2", type: "idea", resurface: "2026-07-20")))
        // 주차 — 마감은 막고 다시 보기는 통과(칸별).
        XCTAssertNil(ItemSchedule.deadlineDay(item("P", type: "parking", due: "2026-07-20")))
        XCTAssertEqual(ItemSchedule.gatedResurface(item("P2", type: "parking", resurface: "2026-07-20")), "2026-07-20")
        // 할일·미분류 — 둘 다 노출.
        XCTAssertEqual(ItemSchedule.deadlineDay(item("A", type: "info-action", due: "2026-07-20")), "2026-07-20")
        XCTAssertEqual(ItemSchedule.gatedResurface(item("A2", type: "info-action", resurface: "2026-07-18")), "2026-07-18")
        XCTAssertEqual(ItemSchedule.deadlineDay(item("U", due: "2026-07-20")), "2026-07-20")   // 미분류 폴백
    }

    // MARK: 게시 게이트도 분류 게이트를 상속한다 (칸별 — 게이트 판정 함수 레벨)

    /// 게시 게이트(`isPublished`)는 분류 게이트를 **상속**한다 — 안 쓰는 칸의 날짜로는 게시되지 않는다.
    /// 위 테스트들은 `publishDay` 레벨이라 판정 함수가 원본 필드를 직접 보게 바뀌면 상속이 조용히 끊길 수 있다.
    /// 칸별이 핵심: 주차는 **마감만** 안 쓰므로 다시 보기로는 게시된다("시간 안 쓰는 분류면 통째로 막힘"이 아님).
    func testGate_isPublishedInheritsClassGate() {
        let cal = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 10))!
        // 주차 — 마감은 안 쓴다 → 마감만으론 게시 안 됨.
        XCTAssertFalse(ItemSchedule.isPublished(item("P", type: "parking", due: "2026-08-31"),
                                                now: now, calendar: cal))
        // 주차 — 다시 보기는 쓴다 → 도래한 다시 보기로는 게시됨.
        XCTAssertTrue(ItemSchedule.isPublished(item("P2", type: "parking", resurface: "2026-07-29"),
                                               now: now, calendar: cal))
        // 아이디어 — 둘 다 안 쓴다 → 미래 마감이 있어도 게시 안 됨.
        XCTAssertFalse(ItemSchedule.isPublished(item("I2", type: "idea", due: "2026-08-31"),
                                                now: now, calendar: cal))
    }

    // MARK: 소비자 상속 — 게이트된 항목은 '사라지는' 게 아니라 시점 없는 쪽으로 옮겨간다

    /// 게이트 걸린 아이디어는 `upcoming`에서 빠지되 **`recent`에 그대로 있다**(유실이면 버그).
    /// (`recent`는 화면에서 확정 여부로 '살아있는 기억' 탭 / '새 기억들' 섹션으로 갈린다.)
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
