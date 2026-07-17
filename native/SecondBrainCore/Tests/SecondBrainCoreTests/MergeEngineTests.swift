import XCTest
@testable import SecondBrainCore

private func h(_ w: Int64, _ c: Int, _ d: String) -> HLC { HLC(wallMillis: w, counter: c, deviceId: d) }

final class MergeEngineTests: XCTestCase {

    // ===== 기본기 =====

    func test01_singleCreate() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "2026-07-16", time: "09:00", source: "voice", raw: "우유")
        ])
        XCTAssertEqual(r.live.count, 1)
        XCTAssertEqual(r.deleted.count, 0)
        XCTAssertEqual(r.item("a")?.raw, "우유")
        XCTAssertEqual(r.item("a")?.deleted, false)
    }

    func test02_sameFieldLaterWins() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x", extra: ["type": "idea"]),
            .edit(id: "a", hlc: h(2, 0, "i"), ["type": "discard"]),
        ])
        XCTAssertEqual(r.item("a")?.type, "discard")
    }

    func test03_differentFieldsBothApply() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x"),
            .edit(id: "a", hlc: h(2, 0, "i"), ["type": "promise"]),
            .edit(id: "a", hlc: h(3, 0, "m"), ["due": "2026-07-20"]),
        ])
        XCTAssertEqual(r.item("a")?.type, "promise")
        XCTAssertEqual(r.item("a")?.due, "2026-07-20")
        XCTAssertEqual(r.item("a")?.raw, "x")
    }

    func test04_orderIndependent() {
        let evs: [Event] = [
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x"),
            .edit(id: "a", hlc: h(2, 0, "i"), ["type": "promise"]),
            .edit(id: "a", hlc: h(3, 0, "m"), ["due": "2026-07-20"]),
            .delete(id: "a", hlc: h(2, 5, "m")),
        ]
        XCTAssertEqual(MergeEngine.merge(evs), MergeEngine.merge(evs.reversed()))
    }

    func test05_idempotent() {
        let evs: [Event] = [
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x"),
            .edit(id: "a", hlc: h(2, 0, "i"), ["type": "idea"]),
        ]
        XCTAssertEqual(MergeEngine.merge(evs), MergeEngine.merge(evs + evs))
    }

    // ===== 급소 1: ID =====

    func test06_twoDevicesDistinctIds() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "iphone 것"),
            .create(id: "b", hlc: h(1, 0, "m"), date: "d", time: "t", source: "doc", raw: "mac 것"),
        ])
        XCTAssertEqual(r.live.count, 2)
    }

    func test07_sameIdMergesNotDuplicated() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x"),
            .edit(id: "a", hlc: h(2, 0, "m"), ["status": "done"]),
        ])
        XCTAssertEqual(r.live.count + r.deleted.count, 1)
        XCTAssertEqual(r.item("a")?.status, "done")
    }

    func test08_editBeforeCreate() {
        let r = MergeEngine.merge([
            .edit(id: "a", hlc: h(2, 0, "m"), ["type": "info"]),
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x"),
        ])
        XCTAssertEqual(r.live.count, 1)
        XCTAssertEqual(r.item("a")?.raw, "x")
        XCTAssertEqual(r.item("a")?.type, "info")
    }

    // ===== 급소 2: 순서 / HLC =====

    func test09_wallDominatesCounter() {
        // wall 9 > 5 이면 counter가 낮아도 승
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x"),
            .edit(id: "a", hlc: h(5, 9, "i"), ["type": "A"]),
            .edit(id: "a", hlc: h(9, 0, "i"), ["type": "B"]),
        ])
        XCTAssertEqual(r.item("a")?.type, "B")
    }

    func test10_counterBreaksSameWall() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x"),
            .edit(id: "a", hlc: h(5, 1, "i"), ["type": "A"]),
            .edit(id: "a", hlc: h(5, 3, "i"), ["type": "B"]),
        ])
        XCTAssertEqual(r.item("a")?.type, "B")
    }

    func test11_deviceIdBreaksTie() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x"),
            .edit(id: "a", hlc: h(5, 2, "aaa"), ["type": "A"]),
            .edit(id: "a", hlc: h(5, 2, "bbb"), ["type": "B"]),
        ])
        XCTAssertEqual(r.item("a")?.type, "B")   // "bbb" > "aaa"
    }

    func test12_causality_slowClockButSawFirst_wins() {
        // A(deviceA, 빠른 물리시계)가 편집. B(deviceB, 느린 물리시계)가 A의 편집을 '보고' 편집.
        var a = HLCClock(deviceId: "A")
        let eA = a.send(now: 100)                       // A: (100,0,A)
        var b = HLCClock(deviceId: "B")                 // B 물리시계는 뒤처짐(50대)
        b.receive(eA, now: 50)                           // A의 이벤트를 관찰 → 시계 끌어올림
        let eB = b.send(now: 51)                         // B: (100,1,B) — wall이 A와 같고 counter 큼
        XCTAssertGreaterThan(eB, eA)                     // 인과성: B가 최신
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "A"), date: "d", time: "t", source: "voice", raw: "x"),
            Event(id: "a", hlc: eA, fields: ["type": "A값"]),
            Event(id: "a", hlc: eB, fields: ["type": "B값"]),
        ])
        XCTAssertEqual(r.item("a")?.type, "B값")         // 순수 wall-clock이면 A가 이겼을 상황
    }

    func test13_offlineConcurrent_deterministic() {
        // 둘 다 오프라인·서로 못 봄 → wall→deviceId로 결정적
        let evs: [Event] = [
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x"),
            .edit(id: "a", hlc: h(7, 0, "iphone"), ["due": "2026-07-18"]),
            .edit(id: "a", hlc: h(7, 0, "mac"), ["due": "2026-07-20"]),
        ]
        let r1 = MergeEngine.merge(evs)
        let r2 = MergeEngine.merge(evs.shuffled())
        XCTAssertEqual(r1, r2)                           // 순서 무관·결정적
        XCTAssertEqual(r1.item("a")?.due, "2026-07-20")  // "mac" > "iphone"
    }

    // ===== 급소 3: 삭제 (정책 P1) =====

    func test14_deleteAfterEdit_hidden() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x"),
            .edit(id: "a", hlc: h(2, 0, "i"), ["type": "idea"]),
            .delete(id: "a", hlc: h(3, 0, "i")),
        ])
        XCTAssertNil(r.live.first { $0.id == "a" })
        XCTAssertEqual(r.deleted.first?.id, "a")
        XCTAssertEqual(r.item("a")?.deleted, true)
    }

    func test15_editAfterDelete_revives() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x"),
            .delete(id: "a", hlc: h(2, 0, "i")),
            .edit(id: "a", hlc: h(3, 0, "m"), ["type": "info"]),   // 삭제보다 나중 → 부활(P1)
        ])
        XCTAssertEqual(r.item("a")?.deleted, false)
        XCTAssertEqual(r.item("a")?.type, "info")
        XCTAssertEqual(r.live.count, 1)
    }

    func test16_deleteVsConcurrentEdit_deterministic() {
        // delete(5,0,iphone) vs edit(5,0,mac): 최고 HLC = mac 편집("mac">"iphone") → 부활(live)
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "iphone"), date: "d", time: "t", source: "voice", raw: "x"),
            .delete(id: "a", hlc: h(5, 0, "iphone")),
            .edit(id: "a", hlc: h(5, 0, "mac"), ["type": "info"]),
        ])
        XCTAssertEqual(r.item("a")?.deleted, false)
        // 반대 방향(삭제가 최고 HLC)이면 숨김 — 결정성 확인
        let r2 = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "iphone"), date: "d", time: "t", source: "voice", raw: "x"),
            .edit(id: "a", hlc: h(5, 0, "iphone"), ["type": "info"]),
            .delete(id: "a", hlc: h(5, 0, "mac")),
        ])
        XCTAssertEqual(r2.item("a")?.deleted, true)
    }

    func test17_deleteThenUndelete() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x"),
            .delete(id: "a", hlc: h(2, 0, "i")),
            .undelete(id: "a", hlc: h(3, 0, "i")),
        ])
        XCTAssertEqual(r.item("a")?.deleted, false)
    }

    func test18_staleReimportDoesNotResurrect() {
        // delete가 최고 HLC(10). 뒤늦게 도착한 오래된 create/edit(1,2)는 못 넘음 → 여전히 삭제
        let r = MergeEngine.merge([
            .delete(id: "a", hlc: h(10, 0, "i")),
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x"),
            .edit(id: "a", hlc: h(2, 0, "m"), ["type": "idea"]),
        ])
        XCTAssertEqual(r.item("a")?.deleted, true)
        XCTAssertTrue(r.live.isEmpty)
    }

    // ===== 연쇄(추가 요청) =====

    func test19b_longChainAlternatingDevices_deterministic() {
        // create → 편집 → 미루기 → 삭제 → 부활, 여러 기기 번갈아. HLC 전순서로 결정적인지.
        let chain: [Event] = [
            .create(id: "a", hlc: h(1, 0, "iphone"), date: "d", time: "t", source: "voice", raw: "이사 계획"),
            .edit(id: "a", hlc: h(2, 0, "mac"), ["type": "info-action"]),
            .edit(id: "a", hlc: h(3, 0, "iphone"), ["resurface": "2026-07-20"]),   // 미루기
            .delete(id: "a", hlc: h(4, 0, "mac")),                                 // 삭제
            .edit(id: "a", hlc: h(5, 0, "iphone"), ["due": "2026-07-19"]),         // 부활(P1) + 시점
        ]
        let r = MergeEngine.merge(chain)
        XCTAssertEqual(r.item("a")?.deleted, false)           // 마지막이 편집 → 부활
        XCTAssertEqual(r.item("a")?.type, "info-action")
        XCTAssertEqual(r.item("a")?.resurface, "2026-07-20")
        XCTAssertEqual(r.item("a")?.due, "2026-07-19")
        // 어떤 순서로 들어와도 같은 결과(결정성)
        for _ in 0..<12 {
            XCTAssertEqual(MergeEngine.merge(chain.shuffled()), r)
        }
    }

    // ===== 견고성 / 포맷 =====

    func test19_garbledEventLineSkipped() {
        let text = """
        - 2026-07-16 09:00 | voice | 정상 create
          id: item-1
          hlc: 100.0.iphone
          type: idea
        이건 깨진 줄 @@@ ||| 아무 의미 없음
        @ 200.0.mac | item-1 | set type=discard
        @ 완전히깨진hlc | item-1 | delete
        @ 300.0.iphone | item-1 | undelete
        """
        let events = EventLog.parse(text)
        // 정상 3개(create, set, undelete)만 파싱, 깨진 2줄은 스킵
        XCTAssertEqual(events.count, 3)
        let r = MergeEngine.merge(events)
        XCTAssertEqual(r.item("item-1")?.type, "discard")
        XCTAssertEqual(r.item("item-1")?.deleted, false)
    }

    func test20_legacyV0LinesIngested() {
        let legacyText = """
        - 2026-06-29 10:40 | voice | 김형석 대표 만나야 됩니다
          type: promise
          due: none
          resurface: weekly
          status: open
        - 2026-07-02 17:24 | voice | 하루를 시작할 때 고민하고 시작하자
          type: principle
        """
        let items = FragmentParser.parse(legacyText, sourceFile: "inbox.md")
        let r = MergeEngine.mergeLegacy(items)
        XCTAssertEqual(r.live.count, 2)
        XCTAssertTrue(r.live.contains { $0.type == "promise" && $0.raw == "김형석 대표 만나야 됩니다" })
        XCTAssertTrue(r.live.contains { $0.type == "principle" })
    }

    // 급소: 레거시 항목(원문 id)에 행동을 붙여도 변이 이벤트 줄이 파싱 왕복돼야 한다.
    // 레거시 id가 "date time|source|raw"라면 `@ hlc | id | verb`가 '|'로 쪼개져 유실됨 → 해시 id로 방지.
    func test21_legacyItemMutationRoundtrips() {
        // 1) 웹 inbox.md 한 줄(id 없음) + 2) 그 항목을 이 기기가 미루기·삭제 → 각각 파일에.
        let legacyLine = "- 2026-06-29 10:40 | voice | 김형석 대표 만나야 됩니다\n  type: promise"
        let legacyId = Event.legacyID(date: "2026-06-29", time: "10:40",
                                      source: "voice", raw: "김형석 대표 만나야 됩니다")
        XCTAssertFalse(legacyId.contains("|"), "레거시 id에 '|'가 있으면 변이 줄이 깨진다")
        XCTAssertFalse(legacyId.contains(" "), "레거시 id에 공백이 있으면 변이 줄이 깨진다")

        // 이 기기 조각: 미루기(resurface) 후 삭제 — 각각 EventWriter로 직렬화한 실제 줄
        let deferEv = Event.edit(id: legacyId, hlc: HLC(wallMillis: 100, counter: 0, deviceId: "mac"),
                                 ["resurface": "2026-07-24"])
        let delEv = Event.delete(id: legacyId, hlc: HLC(wallMillis: 200, counter: 0, deviceId: "mac"))
        let fragment = EventWriter.serialize(deferEv) + "\n" + EventWriter.serialize(delEv)

        // inbox.md(레거시) + 기기 조각을 함께 병합
        let r = InboxStore.merge(fragmentTexts: [legacyLine, fragment])

        // 삭제가 최신 HLC → 숨김(tombstone), 그리고 그 tombstone에 미루기 값이 반영돼 있어야(왕복 성공 증거)
        XCTAssertTrue(r.live.isEmpty, "삭제가 최신이라 live엔 없어야")
        XCTAssertEqual(r.item(legacyId)?.deleted, true)
        XCTAssertEqual(r.item(legacyId)?.resurface, "2026-07-24", "미루기 이벤트가 파싱 왕복돼 반영돼야")
        XCTAssertEqual(r.item(legacyId)?.type, "promise", "레거시 콘텐츠도 유지")
    }
}
