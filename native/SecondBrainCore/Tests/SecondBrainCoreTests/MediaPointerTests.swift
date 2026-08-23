import XCTest
@testable import SecondBrainCore

/// ★ **이것은 「결정을 지키는 시험」이다**(`CLAUDE.md` 「시험을 쓰는 법」).
///
/// ① **무슨 결정인가** — 자료 포인터는 **자료마다 별도 필드**(`photo.<자료id>`)다.
///    2026-08-23 사용자 결정 · `docs/native/media-expansion-design.md` **§3-W**(요약) · **§3-V-1**(안 셋).
///    안 고른 것: **㉮ 한 필드에 쉼표 목록**(⛔ 자료가 사라진다 — 아래 대조군) ·
///    **㉰ 자료를 별도 항목/이벤트로**(데이터 모델이 바뀐다).
///
/// ② **사실(지금 동작이 왜 맞는가)** — 병합은 항목별·필드별 LWW다(`merge-design.md` §3).
///    **다른 필드는 둘 다 산다. 같은 필드는 하나만 산다.** 그래서 꼴이 손실을 정한다.
///    그리고 **자료 id는 소문자 16진(하이픈 없음)**이어야 한다 — 파서 제약이다(아래 시험 5).
///
/// ③ **깨지면 무엇을 의심하나** — 구현이 아니라 **누가 왜 꼴을 바꿨나**를 먼저 본다.
///    - 시험 1이 깨졌다 → 병합 규칙이나 포인터 꼴이 바뀌었다. **§3-W와 `merge-design.md` §3을 함께 본다.**
///    - 시험 2(대조군)가 깨졌다 → **이 시험 묶음이 판별력을 잃었다.** 1이 통과해도 증거가 아니다.
///    - 시험 5가 깨졌다 → **`EventLog.parse`의 키 charset을 넓힌 것이다.** 그러면 `MediaPointer`의
///      「소문자 16진」 제약을 완화할 수 있는지 다시 본다(넓히는 것은 왕복 계약을 건드린다).
///    - 시험 8이 깨졌다 → **create 블록 화이트리스트를 연 것이다**(제약 10 = 성역 경계 설계).
///      그때는 **시험 5의 하이픈 규칙을 반드시 함께** 확인한다 — 성역 포인터가 조용히 사라지는 자리다.
final class MediaPointerTests: XCTestCase {

    private func hlc(_ ms: Int64, _ dev: String) -> HLC {
        HLC(wallMillis: ms, counter: 0, deviceId: dev)
    }

    // MARK: 1) ✅ 별도 필드 — 두 기기가 각각 붙여도 둘 다 산다 (파일 왕복 포함)

    func testTwoDevicesAddDifferentAssets_bothSurvive() {
        let a = MediaPointer.newAssetId()
        let b = MediaPointer.newAssetId()
        let macAdds = Event.edit(id: "p1", hlc: hlc(10, "mac"),
                                 [MediaPointer.key(.photo, a): "\(a).jpg"])
        let phoneAdds = Event.edit(id: "p1", hlc: hlc(11, "iphone"),
                                   [MediaPointer.key(.photo, b): "\(b).jpg"])

        // 조각 파일에 각각 적히고 합쳐지는 길 그대로: 직렬화 → 파싱 → 병합
        let text = [macAdds, phoneAdds].map(EventWriter.serialize).joined(separator: "\n")
        let item = MergeEngine.merge(EventLog.parse(text)).item("p1")
        XCTAssertEqual(item?.fields[MediaPointer.key(.photo, a)], "\(a).jpg")
        XCTAssertEqual(item?.fields[MediaPointer.key(.photo, b)], "\(b).jpg")

        // 순서무관(merge-design의 계약) — 반대로 읽어도 같다
        let reversed = [phoneAdds, macAdds].map(EventWriter.serialize).joined(separator: "\n")
        XCTAssertEqual(MergeEngine.merge(EventLog.parse(reversed)).item("p1")?.fields, item?.fields)
    }

    // MARK: 2) ⛔ 대조군(㉮ 쉼표 목록) — 하나가 통째로 진다 = **자료가 사라진다**
    //
    // ★ 이 시험은 「안 고른 안」이 실제로 손실을 낸다는 것을 못 박는다.
    //   이것이 통과할 때에만 시험 1이 「꼴을 갈라내는 증거」가 된다
    //   (`CLAUDE.md` 계측 규칙 7 — *"비교가 통과했다는 것은 표본이 그 차이를 드러낼 수 있었을 때만 증거다"*).

    func testCommaListForm_losesOneAsset_thisIsWhyWeRejectedIt() {
        // 두 기기가 각자 「a.jpg가 이미 있는」 상태에서 한 장씩 더 붙인다 → 같은 `photo` 필드에 각자의 목록
        let macList = Event.edit(id: "p2", hlc: hlc(10, "mac"), ["photo": "a.jpg,b.jpg"])
        let phoneList = Event.edit(id: "p2", hlc: hlc(11, "iphone"), ["photo": "a.jpg,c.jpg"])
        let text = [macList, phoneList].map(EventWriter.serialize).joined(separator: "\n")
        let merged = MergeEngine.merge(EventLog.parse(text)).item("p2")

        // 같은 필드 → HLC 최신 하나만 남는다. 낮은 쪽 목록은 통째로 사라진다(b.jpg가 없다).
        XCTAssertEqual(merged?.fields["photo"], "a.jpg,c.jpg")
        XCTAssertFalse(merged?.fields["photo"]?.contains("b.jpg") ?? true, "쉼표 목록은 손실이 난다")
    }

    // MARK: 3·4) 포인터 필드가 두 왕복 경로를 다 통과한다

    func testPointerField_roundtrips_setPath() {
        let id = MediaPointer.newAssetId()
        let k = MediaPointer.key(.photo, id)
        let e = Event.edit(id: "p3", hlc: hlc(5, "mac"), [k: "\(id).jpg"])
        let s = EventWriter.serialize(e)
        XCTAssertTrue(s.contains("| set "))                 // 공백 없는 값 → 평문 set
        XCTAssertEqual(EventLog.parse(s).first?.fields[k], "\(id).jpg")
    }

    func testPointerField_roundtrips_editBlockPath() {
        let id = MediaPointer.newAssetId()
        let k = MediaPointer.key(.photo, id)
        let e = Event.edit(id: "p4", hlc: hlc(6, "mac"), [k: "지하 2층 사진.jpg"])   // 공백 → fields.v1
        let s = EventWriter.serialize(e)
        XCTAssertTrue(s.contains("fields.v1:"))
        XCTAssertEqual(EventLog.parse(s).first?.fields[k], "지하 2층 사진.jpg")
    }

    // MARK: 5) ⛔ 왜 자료 id가 「소문자 16진·하이픈 없음」인가 — 파서가 그 줄을 조용히 버린다
    //
    // 필드 줄(create 블록·편집 블록)의 키는 `[A-Za-z0-9_.]+`로만 읽히고 `lowercased()`된다.
    // ⚠️ **`UUID().uuidString`(대문자+하이픈)을 키에 쓰면 값이 사라지고 아무 신호도 없다.**

    func testFieldLineKey_hyphenIsSilentlyDropped_uppercaseIsFolded() {
        func parseFieldLine(_ key: String) -> [String: String] {
            let text = """
            - 2026-08-23 10:00 | image | x
              id: c1
              hlc: 1-0-d
              \(key): a.jpg
            """
            return EventLog.parse(text).first?.fields ?? [:]
        }

        // ⛔ 하이픈 → 그 줄이 통째로 스킵된다(키도 값도 없다)
        let hyphen = "photo.4c0882a0-1111-2222-3333-444455556666"
        XCTAssertNil(parseFieldLine(hyphen)[hyphen])
        XCTAssertTrue(parseFieldLine(hyphen).keys.filter { $0.hasPrefix("photo") }.isEmpty)

        // ⛔ 대문자 → 소문자로 접혀 **다른 키**가 된다(왕복이 깨진다)
        let upper = "photo.4C0882A01111222233334444555566667777"
        XCTAssertNil(parseFieldLine(upper)[upper])
        XCTAssertEqual(parseFieldLine(upper)[upper.lowercased()], "a.jpg")

        // ✅ 소문자 16진 → 그대로 읽힌다. `newAssetId()`가 이 꼴을 만든다.
        let ok = MediaPointer.key(.photo, MediaPointer.newAssetId())
        XCTAssertEqual(parseFieldLine(ok)[ok], "a.jpg")
    }

    // MARK: 6) 자료 id 꼴 — 항목 id 꼴(`UUID().uuidString`)을 키로 쓰지 못하게 막는다

    func testAssetIdForm() {
        let id = MediaPointer.newAssetId()
        XCTAssertEqual(id.count, 32)
        XCTAssertTrue(MediaPointer.isValidAssetId(id))
        XCTAssertFalse(id.contains("-"))
        XCTAssertEqual(id, id.lowercased())
        XCTAssertFalse(MediaPointer.isValidAssetId(UUID().uuidString))   // 항목 id 꼴은 키에 못 쓴다
        XCTAssertFalse(MediaPointer.isValidAssetId(""))
    }

    // MARK: 7) 옛 단일 필드와 공존 — 옛 파일은 이름을 안 바꾼다(§6)

    func testPointers_readsOldSingleFieldTogetherWithNewOnes() {
        let a = "0000000000000000000000000000000a"
        let b = "0000000000000000000000000000000b"
        let fields = [
            "photo": "OLD-ITEM-ID.jpg",                     // 옛 꼴(값은 항목 id — 값이라 제약 없음)
            MediaPointer.key(.photo, b): "\(b).jpg",
            MediaPointer.key(.photo, a): "\(a).jpg",
            MediaPointer.key(.audio, a): "\(a).m4a",        // 다른 종류는 안 섞인다
            "raw": "주차 위치",
        ]
        let photos = MediaPointer.pointers(.photo, in: fields)
        XCTAssertEqual(photos.map(\.value), ["OLD-ITEM-ID.jpg", "\(a).jpg", "\(b).jpg"])
        XCTAssertNil(photos.first?.assetId)                 // 옛 단일 필드는 자료 id가 없다
        XCTAssertEqual(MediaPointer.pointers(.audio, in: fields).map(\.value), ["\(a).m4a"])
        XCTAssertNil(MediaPointer.parse("raw"))
        XCTAssertEqual(MediaPointer.parse("photo")?.assetId, nil)
    }

    // MARK: 8) 지금 사실: create 블록(성역)은 아직 자료 필드를 안 쓴다 — 화이트리스트가 고정 목록이다
    //
    // ⛔ 이 시험이 깨진다면 구현이 틀린 것이 아니라 **화이트리스트를 연 것**이다(제약 10 · 성역 경계).
    //   그때는 시험 5의 하이픈 규칙을 함께 본다 — 성역 포인터가 조용히 사라질 수 있는 자리다.

    func testCreateBlock_doesNotYetCarryAssetFields() {
        let id = MediaPointer.newAssetId()
        let k = MediaPointer.key(.photo, id)
        let c = Event.create(id: "c9", hlc: hlc(1, "iphone"),
                             date: "2026-08-23", time: "10:00", source: "image", raw: "주차 위치",
                             extra: [k: "\(id).jpg", "photo": "c9.jpg"])
        let s = EventWriter.serialize(c)
        XCTAssertFalse(s.contains(k))                                    // 새 꼴은 아직 안 쓰인다
        // (아래 B 시험들과 짝 — 이 시험이 깨지면 성역 경계 설계가 열린 것이다)
        XCTAssertEqual(EventLog.parse(s).first?.fields["photo"], "c9.jpg")  // 옛 단일 필드는 그대로 성역
    }

    // MARK: - B. 파일명 = `<항목id>-<자료id>.<확장자>` (2026-08-23 사용자 결정 ㉰ · §3-W-6)
    //
    // ⛔ 깨지면 무엇을 의심하나: 구현이 아니라 **파일명 꼴을 바꾼 것**이다 — §3-W-6과 §3-V-2를 함께 본다.
    //   ⚠️ 꼴을 바꾸면 **이미 저장된 파일이 안 찾힌다**(포인터 값이 곧 파일명이다).

    // 9) 새 꼴과 옛 꼴을 가른다 — 가르는 근거는 「항목 id에는 하이픈이 있고 자료 id에는 없다」
    func testFilename_newFormAndOldFormAreDistinguished() {
        let itemId = "495BA146-2191-4495-9837-804FC427FAD3"     // 항목 id 꼴(대문자+하이픈) 그대로
        let assetId = MediaPointer.newAssetId()

        let name = MediaPointer.filename(.photo, itemId: itemId, assetId: assetId)
        XCTAssertEqual(name, "\(itemId)-\(assetId).jpg")
        let parsed = MediaPointer.parseFilename(name)
        XCTAssertEqual(parsed?.itemId, itemId)                  // 항목 id 안의 하이픈이 살아서 돌아온다
        XCTAssertEqual(parsed?.assetId, assetId)

        // 옛 단일 파일 — 이름을 안 바꾼다(§6). 자료 id가 없다.
        let old = MediaPointer.parseFilename("\(itemId).jpg")
        XCTAssertEqual(old?.itemId, itemId)
        XCTAssertNil(old?.assetId)

        // 음성도 같은 꼴, 확장자만 다르다
        XCTAssertEqual(MediaPointer.filename(.audio, itemId: itemId, assetId: assetId),
                       "\(itemId)-\(assetId).m4a")
        XCTAssertNil(MediaPointer.parseFilename("확장자없음"))
    }

    // 10) ⛔ 대조군(㉮ `<항목id>-<n>`) — **두 기기가 같은 이름을 만든다 = 파일이 덮인다**
    //   ★ 자료 id 꼴은 두 기기가 독립적으로 만들어도 절대 안 겹친다. 그것이 ㉮와 갈리는 자리다.
    func testFilename_independentDevicesNeverCollide_unlikeIndexForm() {
        let itemId = "495BA146-2191-4495-9837-804FC427FAD3"

        // ㉮였다면: 두 기기가 각자 「이미 한 장 있으니 다음은 2번」이라고 셈한다 → 같은 이름
        let macIndexName = "\(itemId)-2.jpg"
        let phoneIndexName = "\(itemId)-2.jpg"
        XCTAssertEqual(macIndexName, phoneIndexName, "㉮는 두 기기가 같은 파일명을 만든다(덮어쓴다)")

        // ㉰: 각 기기가 제 자료 id를 만든다 → 이름이 다르다
        let macName = MediaPointer.filename(.photo, itemId: itemId, assetId: MediaPointer.newAssetId())
        let phoneName = MediaPointer.filename(.photo, itemId: itemId, assetId: MediaPointer.newAssetId())
        XCTAssertNotEqual(macName, phoneName)

        // 그리고 이름이 포인터 **값**으로 그대로 들어가도 평문 경로가 견딘다(공백·'|' 없음)
        XCTAssertTrue(EventWriter.isPlaintextSafe(macName))
    }

    // 11) 포인터와 파일명이 한 자료를 가리킨다 — 필드 이름의 자료 id = 파일명의 자료 id
    func testPointerAndFilename_agreeOnAssetId() {
        let itemId = "7A23C13E-E4F8-4559-9F76-749D97E80CE7"
        let assetId = MediaPointer.newAssetId()
        let fields = [MediaPointer.key(.photo, assetId): MediaPointer.filename(.photo, itemId: itemId, assetId: assetId)]

        let ptr = MediaPointer.pointers(.photo, in: fields).first
        XCTAssertEqual(ptr?.assetId, assetId)
        XCTAssertEqual(MediaPointer.parseFilename(ptr?.value ?? "")?.assetId, assetId)
        XCTAssertEqual(MediaPointer.parseFilename(ptr?.value ?? "")?.itemId, itemId)   // 파일만 봐도 어느 기억 것인지 안다
    }
}
