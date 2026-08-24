import XCTest
@testable import SecondBrainCore

/// ★ **이것은 「결정을 지키는 시험」이다**(`CLAUDE.md` 「시험을 쓰는 법」).
///
/// ① **무슨 결정인가** — **URL은 포인터 「값」에 URL 문자열을 그대로 담는다. 파일을 만들지 않는다.**
///    2026-08-24 사용자 결정 · `docs/native/media-expansion-design.md` **§3-Z-2 A**.
///    안 고른 것: ㉯ **URL도 한 줄짜리 파일로**(기존 갈래를 재사용하지만 iCloud에 파일이 늘고
///    평문 자산이 한 겹 뒤로 간다) · ㉰ **URL+제목을 함께**(한 필드 값 안에 구조가 생긴다).
///
/// ② **사실(지금 동작이 왜 맞는가)** — 2026-08-24 맥북에서 **쟀다**(§3-Z-3):
///    실제 URL 열 꼴이 **전부 무손실 왕복**한다. 공백·`|`가 든 값은 `set k=v`가 못 담는데
///    `EventWriter`가 **스스로 `fields.v1`(JSON)로 우회**한다 — 그 게이트(`roundTrips`)가 이미 있었다.
///    그리고 **파일 층(`MediaKind`)에는 `url`이 없다** — 그래서 업로드·받아오기·들여오기가
///    URL을 **그냥 못 본다.** 막는 코드가 아니라 **타입이 막는다.**
///
/// ③ **깨지면 무엇을 의심하나** — 구현이 아니라 **누가 왜 꼴을 바꿨나**를 먼저 본다.
///    - 시험 1이 깨졌다 → **`EventWriter`의 우회로(`fields.v1`)나 `roundTrips` 게이트를 건드린 것이다.**
///      그러면 URL 자료가 **조용히 잘려 저장된다**(값이 사라져도 아무 신호가 없다). §3-Z-3을 다시 본다.
///    - 시험 2가 깨졌다 → **`MediaKind`에 `url`을 더한 것이다.** ⛔ 그러면 업로더가 URL을 파일로 보고
///      올리려 든다. **URL을 파일로 만들기로 결정을 뒤집은 것이 아닌지** §3-Z-2 A를 확인한다.
///    - 시험 3(대조군)이 깨졌다 → **이 묶음이 판별력을 잃었다.** 1·2가 통과해도 증거가 아니다.
final class MediaPointerURLTests: XCTestCase {

    private func hlc(_ ms: Int64, _ dev: String = "mac") -> HLC {
        HLC(wallMillis: ms, counter: 0, deviceId: dev)
    }

    // MARK: 1) ✅ URL 값이 무손실 왕복한다 — 쟀던 열 꼴 그대로

    func testURLValuesRoundTripLossless() {
        // ⚠️ 이 목록은 2026-08-24에 **실제로 재서** 정한 것이다(§3-Z-3). 줄이지 말 것 —
        // 「공백 있음」·「| 있음」이 `fields.v1` 우회로를 밟는 **유일한 표본**이다.
        let urls = [
            "https://example.com/a/b",
            "https://example.com/s?q=1&x=2#frag",
            "https://a.io/p?a=b=c&d==",
            "https://ko.wikipedia.org/wiki/이차_기억",
            "https://example.com/%E2%9C%93?q=%20",
            "https://example.com/a b",                 // 공백 — set k=v가 못 담는다
            "https://example.com/a|b",                 // | — 같다
            "https://example.com/?q=" + String(repeating: "x", count: 2000),
            "https://example.com/a(b),c",
            "https://u:p@example.com:8443/x",
            // 실데이터에서 온 둘 (inbox*.md · 2026-08-24)
            "https://wowanalytica.com",
            "https://questionablyepic.com",
        ]
        for url in urls {
            let assetId = MediaPointer.newAssetId()
            let key = MediaPointer.key(.url, assetId)
            let e = Event.edit(id: "p1", hlc: hlc(10), [key: url])
            let back = MergeEngine.merge(EventLog.parse(EventWriter.serialize(e))).item("p1")?.fields[key]
            XCTAssertEqual(back, url, "URL 값이 왕복하지 않았다 — 조용히 잘린다")
        }
    }

    // MARK: 2) ✅ URL은 파일이 아니다 — 파일 층이 URL을 못 본다

    func testURLIsNotAFile() {
        XCTAssertNil(MediaPointer.Kind.url.fileKind)
        XCTAssertNil(MediaPointer.Kind.url.ext)
        XCTAssertFalse(MediaPointer.Kind.url.valueIsFilename)

        // ⛔ 파일 층에 url이 있으면 업로더·받아오기가 URL을 파일로 보고 움직인다.
        XCTAssertFalse(MediaKind.allCases.contains { $0.rawValue == "url" })
    }

    // MARK: 3) ⚠️ 대조군 — 사진·음성은 여전히 파일이다 (2가 통과해도 이것이 깨지면 증거가 아니다)

    func testFileKindsStillFiles() {
        XCTAssertEqual(MediaPointer.Kind.photo.fileKind, .photo)
        XCTAssertEqual(MediaPointer.Kind.audio.fileKind, .audio)
        XCTAssertEqual(MediaPointer.Kind.photo.ext, "jpg")
        XCTAssertEqual(MediaPointer.Kind.audio.ext, "m4a")
        XCTAssertTrue(MediaPointer.Kind.photo.valueIsFilename)
        XCTAssertTrue(MediaPointer.Kind.audio.valueIsFilename)
    }

    // MARK: 4) ✅ 두 기기가 URL을 각각 붙여도 둘 다 산다 (별도 필드라서)

    func testTwoDevicesAddURLs_bothSurvive() {
        let a = MediaPointer.newAssetId(), b = MediaPointer.newAssetId()
        let mac = Event.edit(id: "p1", hlc: hlc(10, "mac"),
                             [MediaPointer.key(.url, a): "https://a.example/1"])
        let phone = Event.edit(id: "p1", hlc: hlc(11, "iphone"),
                               [MediaPointer.key(.url, b): "https://b.example/2"])
        let text = [mac, phone].map(EventWriter.serialize).joined(separator: "\n")
        let item = MergeEngine.merge(EventLog.parse(text)).item("p1")
        XCTAssertEqual(item?.fields[MediaPointer.key(.url, a)], "https://a.example/1")
        XCTAssertEqual(item?.fields[MediaPointer.key(.url, b)], "https://b.example/2")
        XCTAssertEqual(MediaPointer.pointers(.url, in: item?.fields ?? [:]).count, 2)
    }

    // MARK: 5) ✅ 종류가 안 섞인다 — 사진 포인터가 URL 목록에 안 들어온다

    func testKindsDoNotMix() {
        let a = MediaPointer.newAssetId()
        let fields = [
            MediaPointer.key(.url, a):   "https://example.com/x",
            MediaPointer.key(.photo, a): "IT-\(a).jpg",
        ]
        XCTAssertEqual(MediaPointer.pointers(.url, in: fields).map(\.value), ["https://example.com/x"])
        XCTAssertEqual(MediaPointer.pointers(.photo, in: fields).map(\.value), ["IT-\(a).jpg"])
    }
}
