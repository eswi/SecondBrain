import XCTest
@testable import SecondBrainCore

final class EventWriterTests: XCTestCase {

    func testSerializeParseRoundtrip_setEdit() {
        let e = Event.edit(id: "x", hlc: HLC(wallMillis: 5, counter: 2, deviceId: "mac"),
                           ["type": "discard", "due": "2026-07-20"])
        let back = EventLog.parse(EventWriter.serialize(e))
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].id, "x")
        XCTAssertEqual(back[0].hlc, e.hlc)
        XCTAssertEqual(back[0].fields["type"], "discard")
        XCTAssertEqual(back[0].fields["due"], "2026-07-20")
    }

    func testSerializeParseRoundtrip_deleteUndelete() {
        let del = Event.delete(id: "x", hlc: HLC(wallMillis: 7, counter: 0, deviceId: "iphone"))
        let un = Event.undelete(id: "x", hlc: HLC(wallMillis: 8, counter: 0, deviceId: "iphone"))
        XCTAssertEqual(EventLog.parse(EventWriter.serialize(del)).first?.fields["deleted"], "true")
        XCTAssertEqual(EventLog.parse(EventWriter.serialize(un)).first?.fields["deleted"], "false")
    }

    func testSerializeParseRoundtrip_create() {
        let c = Event.create(id: "c1", hlc: HLC(wallMillis: 1, counter: 0, deviceId: "iphone"),
                             date: "2026-07-16", time: "09:00", source: "voice", raw: "우유 사오기",
                             extra: ["type": "info-action"])
        let back = EventLog.parse(EventWriter.serialize(c))
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].id, "c1")
        XCTAssertEqual(back[0].hlc, c.hlc)
        XCTAssertEqual(back[0].fields["raw"], "우유 사오기")
        XCTAssertEqual(back[0].fields["source"], "voice")
        XCTAssertEqual(back[0].fields["type"], "info-action")
    }

    // 앱이 하는 것: 조각 파일에 이벤트 append → 다시 읽어 병합에 반영되는가 (쓰기→읽기 왕복).
    func testAppendThenLoadReflects() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbwrite-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 기기 조각에 create 하나
        let devFile = dir.appendingPathComponent("inbox-dev1.md")
        try EventWriter.append(
            .create(id: "a", hlc: HLC(wallMillis: 10, counter: 0, deviceId: "dev1"),
                    date: "2026-07-16", time: "09:00", source: "voice", raw: "지울 항목",
                    extra: ["type": "idea"]),
            to: devFile)

        var r = InboxStore.loadDirectory(dir).result
        XCTAssertEqual(r.live.count, 1)
        XCTAssertEqual(r.item("a")?.deleted, false)

        // 삭제 이벤트 append (더 높은 HLC) → 다시 읽으면 숨김
        try EventWriter.append(
            .delete(id: "a", hlc: HLC(wallMillis: 20, counter: 0, deviceId: "dev1")),
            to: devFile)
        r = InboxStore.loadDirectory(dir).result
        XCTAssertTrue(r.live.isEmpty)
        XCTAssertEqual(r.item("a")?.deleted, true)
    }

    // 시계: 직렬화 왕복 + 앱 재시작(persisted last에서 복원)해도 단조 증가.
    func testHLCSerializeRoundtrip() {
        let h = HLC(wallMillis: 1721, counter: 3, deviceId: "iphone.pro")
        XCTAssertEqual(HLC(serialized: h.serialized), h)   // deviceId에 '.' 있어도 복원
    }

    func testClockMonotonicAcrossRestart() {
        var c1 = HLCClock(deviceId: "d")
        let a = c1.send(now: 100)
        let persisted = c1.last                            // 앱 저장
        var c2 = HLCClock(deviceId: "d", last: persisted)  // 앱 재시작 복원
        let b = c2.send(now: 100)                          // 물리시간 안 늘어도
        XCTAssertGreaterThan(b, a)                         // 단조 증가 유지
    }
}
