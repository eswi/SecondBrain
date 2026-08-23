import XCTest
@testable import SecondBrainCore

/// **자료의 iCloud 자리 판정과 자리 로그** (설계 `docs/native/media-icloud-design.md` §2 · 2026-08-19).
///
/// 이 시험이 지키는 것은 셋이다:
/// 1. **갈림이 한 자리에서 끝난다** — 하위 폴더가 되든 안 되든 바뀌는 것은 상대 경로 하나.
/// 2. **로그가 세 상태를 갈라 말한다** — 「폴더가 있다」 · 「만들려다 실패해서 루트로 갔다」 ·
///    「아직 아무것도 안 적혔다」. 이 갈림이 없으면 **조용히 폴백으로 넘어간 것을 못 본다**(사용자 지시).
/// 3. **정상이면 파일이 안 자란다** — 「바뀔 때만」. 진단용 파일이 노이즈로 덮이지 않게.
final class MediaPlaceTests: XCTestCase {

    // MARK: 1. 자리 판정과 상대 경로

    func testPlace_subdirReady가_자리를_정한다() {
        XCTAssertEqual(MediaPlaceJudge.place(subdirReady: true), .subdir)
        XCTAssertEqual(MediaPlaceJudge.place(subdirReady: false), .root)
    }

    func testRelativePath_하위폴더면_종류별_폴더_아래() {
        XCTAssertEqual(MediaPlaceJudge.relativePath(kind: .audio, name: "82B1044B.m4a", place: .subdir),
                       "audio/82B1044B.m4a")
        XCTAssertEqual(MediaPlaceJudge.relativePath(kind: .photo, name: "82B1044B.jpg", place: .subdir),
                       "photo/82B1044B.jpg")
    }

    func testRelativePath_폴백이면_루트에_접두사() {
        XCTAssertEqual(MediaPlaceJudge.relativePath(kind: .audio, name: "82B1044B.m4a", place: .root),
                       "sb-82B1044B.m4a")
        XCTAssertEqual(MediaPlaceJudge.relativePath(kind: .photo, name: "82B1044B.jpg", place: .root),
                       "sb-82B1044B.jpg")
    }

    /// **폴백 이름이 `inbox*.md`와 안 섞여야 한다** — 루트에 두는 것을 감수하는 조건이 그것이다(§2).
    /// `FragmentFolder.read()`가 `inbox` 접두사 + `.md`만 글롭하므로 `sb-` 접두사는 절대 안 걸린다.
    func testRelativePath_폴백이_조각파일_글롭에_안_걸린다() {
        for kind in MediaKind.allCases {
            let p = MediaPlaceJudge.relativePath(kind: kind, name: "0E4B8C7F.\(kind.ext)", place: .root)
            XCTAssertFalse(p.hasPrefix("inbox"), p)
            XCTAssertNotEqual((p as NSString).pathExtension, "md", p)
        }
    }

    /// 확장자는 로컬 저장소(`AudioStore.filename`/`PhotoStore.filename`)와 **같아야** 한다 —
    /// 다르면 「로컬에 있는데 iCloud에 없는 것」 차집합이 영원히 안 비고 매번 다시 올린다.
    func testExt_로컬_파일명과_같다() {
        XCTAssertEqual(MediaKind.audio.ext, "m4a")
        XCTAssertEqual(MediaKind.photo.ext, "jpg")
    }

    // MARK: 2. 로그 한 줄

    private let ts = "2026-08-19T12:10:33+09:00"

    func testLine_성공은_원인칸이_없다() {
        let r = MediaPlaceRecord(kind: .audio, place: .subdir)
        XCTAssertEqual(MediaPlaceLog.line(at: ts, device: "iphone-4532", r),
                       "2026-08-19T12:10:33+09:00 iphone-4532 audio place=subdir\n")
    }

    /// **원인은 시스템이 준 값 그대로**(`<domain>/<code>`). 해석·번역을 붙이지 않는다.
    func testLine_실패는_원인을_그대로_붙인다() {
        let r = MediaPlaceRecord(kind: .photo, place: .root, err: "NSCocoaErrorDomain/513")
        XCTAssertEqual(MediaPlaceLog.line(at: ts, device: "iphone-4532", r),
                       "2026-08-19T12:10:33+09:00 iphone-4532 photo place=root err=NSCocoaErrorDomain/513\n")
    }

    // MARK: 3. 마지막 기록 읽기 — 세 상태가 갈리나

    func testLast_아직_아무것도_안_적혔으면_nil() {
        XCTAssertNil(MediaPlaceLog.last("", kind: .audio))
        XCTAssertNil(MediaPlaceLog.last("", kind: .photo))
    }

    func testLast_종류별로_따로_읽는다() {
        let text = """
        \(ts) iphone-4532 audio place=subdir
        \(ts) iphone-4532 photo place=root err=NSCocoaErrorDomain/513
        """
        XCTAssertEqual(MediaPlaceLog.last(text, kind: .audio),
                       MediaPlaceRecord(kind: .audio, place: .subdir))
        XCTAssertEqual(MediaPlaceLog.last(text, kind: .photo),
                       MediaPlaceRecord(kind: .photo, place: .root, err: "NSCocoaErrorDomain/513"))
    }

    /// 줄이 셋 이상이면 **마지막이 지금 상태다** — 「세 번째 줄이 있으면 그때 무슨 일이 있었다」.
    func testLast_마지막_줄이_지금_상태다() {
        let text = """
        2026-08-19T12:10:33+09:00 iphone-4532 audio place=subdir
        2026-08-20T13:02:11+09:00 iphone-4532 audio place=root err=NSCocoaErrorDomain/513
        """
        XCTAssertEqual(MediaPlaceLog.last(text, kind: .audio),
                       MediaPlaceRecord(kind: .audio, place: .root, err: "NSCocoaErrorDomain/513"))
    }

    /// 읽을 수 없는 줄은 **지나간다.** 손으로 뭘 적어 넣어도 판정이 안 망가져야 한다 —
    /// 이 파일은 사용자의 iCloud 폴더에 있고 사람이 열어 볼 수 있다.
    func testLast_망가진_줄을_건너뛴다() {
        let text = """
        \(ts) iphone-4532 audio place=subdir
        메모 한 줄
        \(ts) iphone-4532 audio place=없는값
        \(ts) iphone-4532
        """
        XCTAssertEqual(MediaPlaceLog.last(text, kind: .audio),
                       MediaPlaceRecord(kind: .audio, place: .subdir))
    }

    /// 같은 키가 둘인 줄에도 **크래시하지 않는다**(사람이 고친 파일 방어).
    func testLast_같은_키가_둘이어도_안_죽는다() {
        let text = "\(ts) iphone-4532 audio place=subdir place=root"
        XCTAssertEqual(MediaPlaceLog.last(text, kind: .audio)?.place, .subdir)
    }

    // MARK: 4. 「바뀔 때만」

    func testAppend_첫_실행은_반드시_남는다() {
        let r = MediaPlaceRecord(kind: .audio, place: .subdir)
        XCTAssertNotNil(MediaPlaceLog.appendIfChanged(existing: "", at: ts, device: "iphone-4532", r))
    }

    func testAppend_같으면_안_남긴다() {
        let r = MediaPlaceRecord(kind: .audio, place: .subdir)
        let first = MediaPlaceLog.appendIfChanged(existing: "", at: ts, device: "iphone-4532", r)!
        XCTAssertNil(MediaPlaceLog.appendIfChanged(existing: first, at: "2026-09-01T09:00:00+09:00",
                                                  device: "iphone-4532", r))
    }

    /// **자리가 바뀐 순간은 반드시 남는다** — 이 한 줄이 없으면 폴백으로 넘어간 것을 못 본다.
    func testAppend_자리가_바뀌면_남긴다() {
        let ok = MediaPlaceRecord(kind: .audio, place: .subdir)
        let base = MediaPlaceLog.appendIfChanged(existing: "", at: ts, device: "iphone-4532", ok)!
        let fell = MediaPlaceRecord(kind: .audio, place: .root, err: "NSCocoaErrorDomain/513")
        let line = MediaPlaceLog.appendIfChanged(existing: base, at: "2026-08-20T13:02:11+09:00",
                                                device: "iphone-4532", fell)
        XCTAssertEqual(line, "2026-08-20T13:02:11+09:00 iphone-4532 audio place=root err=NSCocoaErrorDomain/513\n")
    }

    /// 자리는 같은데 **원인 코드가 달라진 것도 변화다** — 같은 폴백이라도 이유가 바뀌면 알아야 한다.
    func testAppend_원인이_달라지면_남긴다() {
        let a = MediaPlaceRecord(kind: .audio, place: .root, err: "NSCocoaErrorDomain/513")
        let base = MediaPlaceLog.appendIfChanged(existing: "", at: ts, device: "iphone-4532", a)!
        let b = MediaPlaceRecord(kind: .audio, place: .root, err: "NSCocoaErrorDomain/257")
        XCTAssertNotNil(MediaPlaceLog.appendIfChanged(existing: base, at: ts, device: "iphone-4532", b))
    }

    /// 한 종류가 적혀 있어도 **다른 종류의 첫 줄은 남는다** — 둘이 서로를 가리지 않게.
    func testAppend_종류가_서로를_가리지_않는다() {
        let audio = MediaPlaceRecord(kind: .audio, place: .subdir)
        let base = MediaPlaceLog.appendIfChanged(existing: "", at: ts, device: "iphone-4532", audio)!
        let photo = MediaPlaceRecord(kind: .photo, place: .subdir)
        XCTAssertNotNil(MediaPlaceLog.appendIfChanged(existing: base, at: ts, device: "iphone-4532", photo))
    }

    // MARK: ★ 축이 바뀐 뒤 — **옛 파일이 그대로 찾혀야 한다** (2026-08-23 · C)

    /// ★ **이것은 「결정을 지키는 시험」이다**(`CLAUDE.md` 「시험을 쓰는 법」).
    ///
    /// ① **무슨 결정** — 조회의 축을 **항목 id → 파일명**으로 바꿨다(`media-expansion-design.md` §3-X).
    /// ② **사실** — 옛 이름(`<항목id>.<확장자>`)을 넣으면 **경로가 글자 그대로 같다.**
    ///    그래서 **이미 iCloud에 올라간 파일 135개가 그대로 찾힌다** — 이름을 바꾸지 않는다(§6).
    /// ③ **깨지면 무엇을 의심하나** — 구현이 아니라 **경로 규칙을 바꾼 것**이다.
    ///    ⛔ 그러면 **기존 파일이 안 찾히고, 화면은 「아직 못 받음」으로 조용히 보인다.**
    func testRelativePath_옛이름은_옛경로와_글자까지_같다() {
        // 아래 문자열은 **축을 바꾸기 전 코드가 내던 값**이다(2026-08-23 기준 · 손으로 옮겨 적었다).
        XCTAssertEqual(MediaPlaceJudge.relativePath(kind: .audio, name: "82B1044B.m4a", place: .subdir),
                       "audio/82B1044B.m4a")
        XCTAssertEqual(MediaPlaceJudge.relativePath(kind: .photo, name: "82B1044B.jpg", place: .root),
                       "sb-82B1044B.jpg")
    }

    /// 새 꼴(`<항목id>-<자료id>.<확장자>`)도 **같은 규칙 한 줄로** 놓인다 — 갈래를 더하지 않는다.
    func testRelativePath_새이름도_같은_규칙() {
        let name = "495BA146-2191-4495-9837-804FC427FAD3-4c0882a01111222233334444555566667777.jpg"
        XCTAssertEqual(MediaPlaceJudge.relativePath(kind: .photo, name: name, place: .subdir),
                       "photo/" + name)
        XCTAssertEqual(MediaPlaceJudge.relativePath(kind: .photo, name: name, place: .root),
                       "sb-" + name)
    }
}
