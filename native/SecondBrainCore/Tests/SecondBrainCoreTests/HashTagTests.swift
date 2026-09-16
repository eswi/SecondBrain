import XCTest
@testable import SecondBrainCore

/// ★ **이것은 「결정을 지키는 시험」이다**(`CLAUDE.md` 「시험을 쓰는 법」).
///
/// ① **무슨 결정인가** — 해시태그는 **태그마다 필드 하나**(`tag.<id>` = 태그 글)다.
///    2026-09-17 사용자 결정(*"1은 ㉡"*) · `docs/native/hashtag-design.md` §1·§2. 안 고른 것: **한 필드에 쉼표 목록**(시험 2가 손실을 보인다).
///    그리고 **다듬기 규칙**(결정 4): 앞뒤 공백 제거 · 안 공백 허용 · 대소문자 구분.
///
/// ② **사실** — 병합은 항목별·필드별 LWW(`merge-design.md` §3). 다른 필드는 둘 다 살고 같은 필드는 하나만 산다.
///    태그 글은 **값**이므로 공백·한글이 무손실이다(`EventWriter`가 왕복 검증으로 경로를 고른다).
///
/// ③ **깨지면 무엇을 의심하나** — 구현이 아니라 **누가 꼴·규칙을 바꿨나.**
///    - 1이 깨졌다 → 병합 규칙이나 필드 꼴이 바뀌었다. 설계 §2와 `merge-design.md` §3을 함께 본다.
///    - 2(대조군)가 깨졌다 → 이 묶음이 판별력을 잃었다. 1이 통과해도 증거가 아니다.
///    - 4가 깨졋다 → **누가 다듬기 규칙을 바꿨다**(대소문자를 합쳤거나 안 공백을 막았다). 결정 4를 다시 본다.
///    - 6이 깨졌다 → `MediaPointer.Kind`에 `tag`를 넣었거나 접두어가 겹쳤다 — 자료 카드가 태그를 자료로 그린다.
final class HashTagTests: XCTestCase {

    private func hlc(_ ms: Int64, _ dev: String) -> HLC { HLC(wallMillis: ms, counter: 0, deviceId: dev) }

    // MARK: 1) ✅ 별도 필드 — 두 기기가 각각 붙여도 둘 다 산다 (파일 왕복 포함 · 값에 공백·한글)

    func testTwoDevicesAddDifferentTags_bothSurvive() {
        let a = HashTag.newId(), b = HashTag.newId()
        let mac = Event.edit(id: "t1", hlc: hlc(10, "mac"), [HashTag.key(a): "맛집"])
        let phone = Event.edit(id: "t1", hlc: hlc(11, "iphone"), [HashTag.key(b): "서울 근교"])   // 안 공백
        let text = [mac, phone].map(EventWriter.serialize).joined(separator: "\n")
        let item = MergeEngine.merge(EventLog.parse(text)).item("t1")
        XCTAssertEqual(item?.hashtags.map(\.text), ["맛집", "서울 근교"])
        let reversed = [phone, mac].map(EventWriter.serialize).joined(separator: "\n")
        XCTAssertEqual(MergeEngine.merge(EventLog.parse(reversed)).item("t1")?.fields, item?.fields)
    }

    // MARK: 2) ⛔ 대조군 — 쉼표 목록이면 한쪽이 통째로 진다 (그래서 안 골랐다)

    func testCommaList_losesOneTag_thisIsWhyWeRejectedIt() {
        let mac = Event.edit(id: "t2", hlc: hlc(10, "mac"), ["tags": "맛집,카페"])
        let phone = Event.edit(id: "t2", hlc: hlc(11, "iphone"), ["tags": "맛집,장소"])
        let merged = MergeEngine.merge(EventLog.parse([mac, phone].map(EventWriter.serialize).joined(separator: "\n"))).item("t2")
        XCTAssertEqual(merged?.fields["tags"], "맛집,장소")
        XCTAssertFalse(merged?.fields["tags"]?.contains("카페") ?? true, "쉼표 목록은 손실이 난다")
    }

    // MARK: 3) 빈 값 = 지웠다 · 같은 id에 새 값 = 고쳤다

    func testEmptyValueIsDeleted_andSameIdRenames() {
        let a = HashTag.newId(), b = HashTag.newId()
        let add = Event.edit(id: "t3", hlc: hlc(1, "mac"), [HashTag.key(a): "맛집", HashTag.key(b): "카페"])
        let del = Event.edit(id: "t3", hlc: hlc(2, "mac"), [HashTag.key(a): ""])
        let ren = Event.edit(id: "t3", hlc: hlc(3, "mac"), [HashTag.key(b): "Cafe"])
        let item = MergeEngine.merge(EventLog.parse([add, del, ren].map(EventWriter.serialize).joined(separator: "\n"))).item("t3")
        XCTAssertEqual(item?.hashtags, [HashTag.Tag(id: b, text: "Cafe")])
        XCTAssertEqual(EventWriter.serialize(del), "@ \(hlc(2, "mac").serialized) | t3 | set \(HashTag.key(a))=")   // 자료 지우기와 같은 꼴
    }

    // MARK: 4) 다듬기 — 결정 4 그대로

    func testNormalize_followsDecision4() {
        XCTAssertEqual(HashTag.normalize("  맛집  "), "맛집")               // 앞뒤 공백 제거
        XCTAssertEqual(HashTag.normalize("#맛집"), "맛집")                  // 앞의 #은 뗀다(화면이 붙인다)
        XCTAssertEqual(HashTag.normalize("## 맛집"), "맛집")
        XCTAssertEqual(HashTag.normalize("서울 근교"), "서울 근교")          // 안 공백 허용
        XCTAssertEqual(HashTag.normalize("Cafe"), "Cafe")                   // 대소문자 그대로
        XCTAssertNotEqual(HashTag.normalize("Cafe"), HashTag.normalize("cafe"))
        XCTAssertEqual(HashTag.normalize("두\n줄"), "두 줄")                // 안 줄바꿈은 공백으로
        XCTAssertNil(HashTag.normalize("   "))
        XCTAssertNil(HashTag.normalize("#"))
        XCTAssertEqual(HashTag.display("맛집"), "#맛집")
        XCTAssertTrue(HashTag.contains("맛집", in: [HashTag.key(HashTag.newId()): "맛집"]))
        XCTAssertFalse(HashTag.contains("맛집", in: [HashTag.key(HashTag.newId()): "Maatjip"]))
    }

    // MARK: 5) 값에 공백·`|`가 있어도 왕복한다 (블록 경로) · 공백 없으면 평문 set

    func testValueRoundtrips_bothPaths() {
        let a = HashTag.newId()
        let plain = Event.edit(id: "t5", hlc: hlc(5, "mac"), [HashTag.key(a): "맛집"])
        XCTAssertTrue(EventWriter.serialize(plain).contains("| set "))
        XCTAssertEqual(EventLog.parse(EventWriter.serialize(plain)), [plain])
        let spaced = Event.edit(id: "t5", hlc: hlc(6, "mac"), [HashTag.key(a): "서울 근교 | 당일"])
        XCTAssertTrue(EventWriter.serialize(spaced).contains("| edit"))
        XCTAssertEqual(EventLog.parse(EventWriter.serialize(spaced)), [spaced])
    }

    // MARK: 6) `tag.` 필드는 자료 포인터가 아니다 · 키 꼴이 아니면 태그가 아니다

    func testTagFields_areNotMediaPointers_andBadKeysIgnored() {
        let a = HashTag.newId()
        XCTAssertNil(MediaPointer.parse(HashTag.key(a)))
        XCTAssertEqual(HashTag.parseKey(HashTag.key(a)), a)
        XCTAssertNil(HashTag.parseKey("tag.ABC-DEF"))       // 대문자·하이픈
        XCTAssertNil(HashTag.parseKey("tag."))
        XCTAssertNil(HashTag.parseKey("photo.\(a)"))
        // 정렬 = 글 기준(붙인 순서가 아니다)
        let fields = [HashTag.key("b" + a.dropFirst()): "카페", HashTag.key("a" + a.dropFirst()): "맛집", HashTag.key("c" + a.dropFirst()): ""]
        XCTAssertEqual(HashTag.tags(in: fields).map(\.text), ["맛집", "카페"])
    }
}
