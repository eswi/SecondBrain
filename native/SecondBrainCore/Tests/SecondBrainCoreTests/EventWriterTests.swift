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

    // 원본 음성 포인터(audio)는 create 성역 필드로 직렬화·파싱 왕복돼야 한다(설계 audio-capture-design §1).
    func testSerializeParseRoundtrip_audioPointer() {
        let c = Event.create(id: "c2", hlc: HLC(wallMillis: 2, counter: 0, deviceId: "iphone"),
                             date: "2026-07-22", time: "10:00", source: "voice", raw: "음성 메모",
                             extra: ["audio": "c2.m4a"])
        let back = EventLog.parse(EventWriter.serialize(c))
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].fields["audio"], "c2.m4a")   // 성역 포인터 왕복
        XCTAssertEqual(back[0].fields["raw"], "음성 메모")
    }

    // 원본 사진 포인터(photo)도 create 성역 필드로 왕복돼야 한다(photo-capture-design §2, audio 미러).
    func testSerializeParseRoundtrip_photoPointer() {
        let c = Event.create(id: "c3", hlc: HLC(wallMillis: 3, counter: 0, deviceId: "iphone"),
                             date: "2026-07-24", time: "10:00", source: "image", raw: "주차 위치",
                             extra: ["photo": "c3.jpg", "type": "parking"])
        let back = EventLog.parse(EventWriter.serialize(c))
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].fields["photo"], "c3.jpg")   // 성역 포인터 왕복
        XCTAssertEqual(back[0].fields["type"], "parking")
        XCTAssertEqual(back[0].fields["raw"], "주차 위치")
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

    // MARK: fields.v1 편집 블록 (공백 있는 값 — 설계 photo-capture-design.md §3)

    // 공백 있는 값(위치 설명·메모)이 왕복되는가. set k=v가 못 담던 것을 JSON 블록이 담는다.
    func testEditBlock_spacedValuesRoundtrip() {
        let e = Event.edit(id: "p1", hlc: HLC(wallMillis: 5, counter: 0, deviceId: "iphone"),
                           ["location": "지하 2층 B구역, 빨간 기둥 옆", "memo": "엘리베이터 왼쪽 30m"])
        let s = EventWriter.serialize(e)
        XCTAssertTrue(s.contains("| edit"))          // set이 아니라 edit 블록으로
        XCTAssertTrue(s.contains("fields.v1:"))
        XCTAssertTrue(s.contains("지하 2층"))         // 한글 그대로(평문 유지, percent/base64 아님)
        let back = EventLog.parse(s)
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].id, "p1")
        XCTAssertEqual(back[0].hlc, e.hlc)
        XCTAssertEqual(back[0].fields["location"], "지하 2층 B구역, 빨간 기둥 옆")
        XCTAssertEqual(back[0].fields["memo"], "엘리베이터 왼쪽 30m")
    }

    // question(공백 있는 재확인 질문)도 이 경로로 왕복 — 그동안 미지원이던 후속 과제 해소.
    func testEditBlock_questionRoundtrip() {
        let e = Event.edit(id: "q1", hlc: HLC(wallMillis: 3, counter: 0, deviceId: "mac"),
                           ["question": "구체적으로 언제 보낼까?"])
        let back = EventLog.parse(EventWriter.serialize(e))
        XCTAssertEqual(back[0].fields["question"], "구체적으로 언제 보낼까?")
    }

    // 하위호환: 공백 없는 값은 여전히 set k=v(기존 포맷·파일 불변).
    func testEditBlock_spacelessStaysSet() {
        let e = Event.edit(id: "x", hlc: HLC(wallMillis: 5, counter: 2, deviceId: "mac"),
                           ["type": "idea", "due": "2026-07-20"])
        let s = EventWriter.serialize(e)
        XCTAssertTrue(s.contains("| set "))
        XCTAssertFalse(s.contains("fields.v1"))
    }

    // ★ 병합 무변경 확인: JSON 블록으로 온 필드도 per-field LWW로 합쳐진다(엔진 입력이 평평한 필드라서).
    // create(type) + edit블록(location) 두 이벤트 → 둘 다 살아남아야 한다(덩어리로 덮지 않음).
    func testEditBlock_perFieldLWWPreserved() {
        let c = Event.create(id: "p2", hlc: HLC(wallMillis: 1, counter: 0, deviceId: "iphone"),
                             date: "2026-07-23", time: "09:00", source: "image", raw: "주차",
                             extra: ["type": "parking"])
        let edit = Event.edit(id: "p2", hlc: HLC(wallMillis: 2, counter: 0, deviceId: "iphone"),
                              ["location": "지하 2층 B구역"])
        let r = MergeEngine.merge([c, edit])
        let item = r.item("p2")
        XCTAssertEqual(item?.fields["type"], "parking")            // create의 필드 보존
        XCTAssertEqual(item?.fields["location"], "지하 2층 B구역")  // edit 블록의 필드 병합
        XCTAssertEqual(item?.raw, "주차")
    }

    // ★ 두 기기 동시 편집: 서로 다른 필드는 둘 다 생존 / 같은 필드는 높은 HLC 승(B1 덩어리였다면 하나가 사라짐).
    func testEditBlock_twoDeviceConcurrentMerge() {
        // 파일 왕복까지 포함해 검증(직렬화→파싱→병합).
        let macMemo = Event.edit(id: "p3", hlc: HLC(wallMillis: 10, counter: 0, deviceId: "mac"),
                                 ["memo": "소화전 옆 이라고 적어둠"])
        let phoneLoc = Event.edit(id: "p3", hlc: HLC(wallMillis: 11, counter: 0, deviceId: "iphone"),
                                  ["location": "지하 2층 B구역"])
        let text = [macMemo, phoneLoc].map(EventWriter.serialize).joined(separator: "\n")
        let r = MergeEngine.merge(EventLog.parse(text))
        let item = r.item("p3")
        XCTAssertEqual(item?.fields["memo"], "소화전 옆 이라고 적어둠")   // 다른 필드 → 생존
        XCTAssertEqual(item?.fields["location"], "지하 2층 B구역")       // 다른 필드 → 생존
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
