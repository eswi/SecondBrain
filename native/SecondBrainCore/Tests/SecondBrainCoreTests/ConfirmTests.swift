import XCTest
@testable import SecondBrainCore

/// "확정" 개념(edit-policy.md §1~3)의 엔진 정확성을 못박는다.
/// 핵심 정책 = **확정은 단방향**: OR-머지(grow-only) + unconfirm 경로 없음으로 이중 보장.
/// (사용자가 특별히 확인 요청한 경로: 테스트 2·4)
final class ConfirmTests: XCTestCase {

    private func create(_ id: String, hlc: HLC, type: String? = nil) -> Event {
        Event.create(id: id, hlc: hlc, date: "2026-07-15", time: "10:00",
                     source: "voice", raw: "x", extra: type.map { ["type": $0] } ?? [:])
    }

    // 1) confirm 이벤트 → confirmed == true
    func testConfirm_setsFlag() {
        let c = create("a", hlc: HLC(wallMillis: 0, counter: 0, deviceId: "legacy"), type: "info")
        let confirm = Event.confirm(id: "a", hlc: HLC(wallMillis: 10, counter: 0, deviceId: "iphone"))
        let m = MergeEngine.merge([c, confirm])
        XCTAssertTrue(m.item("a")?.confirmed ?? false, "confirm 이벤트가 있으면 확정")
    }

    // 2) [정책 핵심] 확정 후 더 높은 HLC로 편집해도 확정 유지 (편집이 확정을 못 지움)
    func testConfirm_survivesLaterEdit() {
        let c = create("a", hlc: HLC(wallMillis: 0, counter: 0, deviceId: "legacy"), type: "info")
        let confirm = Event.confirm(id: "a", hlc: HLC(wallMillis: 5, counter: 0, deviceId: "iphone"))
        // 확정(hlc=5) 이후 더 최신(hlc=9) 편집 — 분류·시점을 바꿔도 확정은 살아있어야 함
        let laterEdit = Event.edit(id: "a", hlc: HLC(wallMillis: 9, counter: 0, deviceId: "iphone"),
                                   ["type": "promise", "due": "2026-08-01"])
        let m = MergeEngine.merge([c, confirm, laterEdit])
        let it = m.item("a")
        XCTAssertTrue(it?.confirmed ?? false, "확정 후 더 높은 HLC 편집이 와도 확정 유지(단방향)")
        XCTAssertEqual(it?.type, "promise", "편집 자체는 반영(per-field LWW)")
        XCTAssertEqual(it?.due, "2026-08-01")
    }

    // 3) 순서 무관·멱등: 이벤트 순서를 섞거나 confirm이 두 번 와도 동일 결과
    func testConfirm_orderIndependentAndIdempotent() {
        let c = create("a", hlc: HLC(wallMillis: 0, counter: 0, deviceId: "legacy"), type: "info")
        let confirm1 = Event.confirm(id: "a", hlc: HLC(wallMillis: 5, counter: 0, deviceId: "iphone"))
        let confirm2 = Event.confirm(id: "a", hlc: HLC(wallMillis: 7, counter: 0, deviceId: "mac"))
        let edit = Event.edit(id: "a", hlc: HLC(wallMillis: 3, counter: 0, deviceId: "iphone"), ["type": "idea"])

        let a = MergeEngine.merge([c, confirm1, confirm2, edit]).item("a")
        let b = MergeEngine.merge([edit, confirm2, c, confirm1]).item("a")   // 순서 뒤섞음
        XCTAssertEqual(a?.confirmed, true)
        XCTAssertEqual(b?.confirmed, true)
        XCTAssertEqual(a, b, "순서 무관·멱등 — 확정은 OR-머지라 순서·중복에 불변")
    }

    // 4) [정책 핵심] override(분류변경)만으로는 확정 안 됨 (edit-policy §2 귀결)
    func testTypeOverride_doesNotConfirm() {
        let c = create("a", hlc: HLC(wallMillis: 0, counter: 0, deviceId: "legacy"), type: "info")
        // 사람이 분류만 바꿈(=InboxModel.changeType와 동형). confirm 이벤트는 없음.
        let override = Event.edit(id: "a", hlc: HLC(wallMillis: 5, counter: 0, deviceId: "iphone"),
                                  ["type": "promise"])
        let m = MergeEngine.merge([c, override])
        let it = m.item("a")
        XCTAssertEqual(it?.type, "promise", "override는 반영되지만")
        XCTAssertFalse(it?.confirmed ?? true, "override(수정)만으로는 확정되지 않는다 — 확정은 명시적 confirm뿐")
    }

    // 5) 레거시 68개는 처음에 전부 미확정 (자동분류=임시, edit-policy §1)
    func testLegacy_startsUnconfirmed() {
        let legacyText = """
        # 받은함
        - 2026-07-15 10:51 | voice | 주차 위치 B3
          type: info
        - 2026-07-15 11:00 | web | 링크 하나
          type: idea
        """
        let events = EventLog.parse(legacyText)
        let m = MergeEngine.merge(events)
        XCTAssertEqual(m.live.count, 2)
        XCTAssertTrue(m.live.allSatisfy { !$0.confirmed }, "레거시는 마이그레이션 없이 전부 미확정으로 시작")
    }

    // 6) 왕복: confirm 이벤트 직렬화 → 재파싱 → 병합에서 확정 유지 (기존 set 경로 재사용)
    func testConfirm_serializationRoundTrips() {
        let confirm = Event.confirm(id: "legacy:abcd", hlc: HLC(wallMillis: 5, counter: 0, deviceId: "d"))
        let line = EventWriter.serialize(confirm)
        XCTAssertEqual(line, "@ \(confirm.hlc.serialized) | legacy:abcd | set confirmed=true")
        let reparsed = EventLog.parse(line)
        XCTAssertEqual(reparsed.count, 1)
        XCTAssertEqual(reparsed[0].fields["confirmed"], "true")

        let c = create("legacy:abcd", hlc: HLC(wallMillis: 0, counter: 0, deviceId: "legacy"), type: "info")
        XCTAssertTrue(MergeEngine.merge([c] + reparsed).item("legacy:abcd")?.confirmed ?? false)
    }
}
