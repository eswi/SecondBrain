import XCTest
@testable import SecondBrainCore

/// 분류 변경(UI에서 종류 아이콘 → 다른 종류)이 **레거시 68개(legacy: id)** 위에서도
/// 이벤트로 제대로 쌓이고 병합에 반영되는지 못박는다. (사용자가 특별히 확인 요청한 경로)
final class TypeChangeTests: XCTestCase {

    func testLegacyTypeChange_setEventOverridesCreate() {
        // 1) inbox.md 레거시 줄(웹 분류 type=info) → 파싱하면 legacy: id, wall=0 create 이벤트
        let legacyText = """
        # 받은함
        - 2026-07-15 10:51 | voice | 주차 위치 B3
          type: info
        """
        let legacyEvents = EventLog.parse(legacyText)
        XCTAssertEqual(legacyEvents.count, 1)
        let lid = legacyEvents[0].id
        XCTAssertTrue(lid.hasPrefix("legacy:"), "레거시 줄은 legacy: 해시 id를 받아야 함")
        XCTAssertEqual(legacyEvents[0].fields["type"], "info")

        // 2) UI 분류 변경 = 그 id 위에 set type= 이벤트 (InboxModel.changeType가 만드는 것과 동형)
        let edit = Event.edit(id: lid,
                              hlc: HLC(wallMillis: 1_000, counter: 0, deviceId: "iphone"),
                              ["type": "promise"])

        // 3) 직렬화 → 조각 파일 한 줄 → 다시 파싱(왕복). '|'·공백 깨짐 없이 살아남아야 함.
        let line = EventWriter.serialize(edit)
        XCTAssertEqual(line, "@ \(edit.hlc.serialized) | \(lid) | set type=promise")
        let reparsed = EventLog.parse(line)
        XCTAssertEqual(reparsed.count, 1)
        XCTAssertEqual(reparsed[0].id, lid)
        XCTAssertEqual(reparsed[0].fields["type"], "promise")

        // 4) 병합: 레거시 create(type=info, wall=0) + set(type=promise, wall=1000) → type=promise
        let merged = MergeEngine.merge(legacyEvents + reparsed)
        let item = merged.item(lid)
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.type, "promise", "최신 HLC의 type이 이겨야 함(per-field LWW)")
        XCTAssertEqual(item?.raw, "주차 위치 B3", "원문은 그대로")
        XCTAssertFalse(item?.deleted ?? true)
    }

    func testUnclassify_emptyTypeValueRoundTrips() {
        // 버림(discard) 되돌리기 = type을 빈 값으로 set → 미분류. `set type=`가 왕복돼야 함.
        let edit = Event.edit(id: "legacy:abcd", hlc: HLC(wallMillis: 5, counter: 0, deviceId: "d"),
                              ["type": ""])
        let line = EventWriter.serialize(edit)
        XCTAssertEqual(line, "@ \(edit.hlc.serialized) | legacy:abcd | set type=")
        let reparsed = EventLog.parse(line)
        XCTAssertEqual(reparsed.count, 1, "빈 값 set도 이벤트로 살아남아야 함")
        XCTAssertEqual(reparsed[0].fields["type"], "")

        // discard였다가 빈 type로 덮으면 최신 값은 "" (미분류)
        let create = Event.create(id: "legacy:abcd", hlc: HLC(wallMillis: 0, counter: 0, deviceId: "legacy"),
                                  date: "2026-07-15", time: "10:00", source: "voice", raw: "x",
                                  extra: ["type": "discard"])
        let m = MergeEngine.merge([create] + reparsed)
        XCTAssertEqual(m.item("legacy:abcd")?.type, "")
    }

    func testTypeChange_doesNotTouchOtherFields() {
        // create에 due가 있어도 type만 바꾸면 due는 유지(필드별 LWW)
        let create = Event.create(id: "legacy:abcd", hlc: HLC(wallMillis: 0, counter: 0, deviceId: "legacy"),
                                  date: "2026-07-15", time: "10:00", source: "voice", raw: "x",
                                  extra: ["type": "info", "due": "2026-07-20"])
        let edit = Event.edit(id: "legacy:abcd", hlc: HLC(wallMillis: 1, counter: 0, deviceId: "d"),
                              ["type": "event"])
        let m = MergeEngine.merge([create, edit])
        let it = m.item("legacy:abcd")
        XCTAssertEqual(it?.type, "event")
        XCTAssertEqual(it?.due, "2026-07-20", "type만 바꿔도 due 유지")
    }
}
