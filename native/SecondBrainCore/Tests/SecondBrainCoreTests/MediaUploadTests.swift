import XCTest
@testable import SecondBrainCore

/// **첫 실행 한도 · 실패 로그 · 사용자가 고른 문구** (설계 §3·§5·§8 · 2026-08-19).
final class MediaUploadTests: XCTestCase {

    // MARK: 한도 (§5)

    func testLimit_iCloud가_비어_있으면_첫_실행_한도() {
        XCTAssertEqual(MediaUploadJudge.limit(cloudMediaCount: 0), 5)
    }

    /// **하나라도 올라가 있으면 한도가 없다** — 확인 지점은 정확히 한 번이다.
    func testLimit_하나라도_있으면_무제한() {
        XCTAssertNil(MediaUploadJudge.limit(cloudMediaCount: 1))
        XCTAssertNil(MediaUploadJudge.limit(cloudMediaCount: 131))
    }

    func testCapped_나머지가_남았나() {
        XCTAssertTrue(MediaUploadJudge.capped(total: 131, limit: 5))
        XCTAssertFalse(MediaUploadJudge.capped(total: 5, limit: 5))   // 딱 맞으면 남은 것이 없다
        XCTAssertFalse(MediaUploadJudge.capped(total: 3, limit: 5))
        XCTAssertFalse(MediaUploadJudge.capped(total: 131, limit: nil))
    }

    // MARK: 실패 로그

    private let ts = "2026-08-19T12:10:33+09:00"

    func testFailureLine_원인을_그대로() {
        XCTAssertEqual(MediaUploadLog.failureLine(at: ts, device: "iphone-4532", kind: .audio,
                                                 id: "82B1044B", err: "NSCocoaErrorDomain/512"),
                       "2026-08-19T12:10:33+09:00 iphone-4532 upload audio 82B1044B err=NSCocoaErrorDomain/512\n")
    }

    /// **★ 두 로그가 같은 파일에 있어도 서로를 안 가린다.** 업로드 줄이 자리 판정으로 읽히면
    /// 「자리가 바뀌었다」로 오해되고, 그러면 자리 로그가 매 실행 다시 적힌다.
    func testFailureLine_자리_로그_판정에_안_걸린다() {
        let place = MediaPlaceLog.line(at: ts, device: "iphone-4532",
                                       MediaPlaceRecord(kind: .audio, place: .subdir))
        let upload = MediaUploadLog.failureLine(at: ts, device: "iphone-4532", kind: .audio,
                                                id: "82B1044B", err: "NSCocoaErrorDomain/512")
        // 업로드 줄이 뒤에 와도 자리 판정은 앞의 자리 줄을 읽는다.
        XCTAssertEqual(MediaPlaceLog.last(place + upload, kind: .audio),
                       MediaPlaceRecord(kind: .audio, place: .subdir))
        // 업로드 줄만 있으면 자리 기록은 **없는 것**이다.
        XCTAssertNil(MediaPlaceLog.last(upload, kind: .audio))
    }

    /// 업로드 실패가 쌓여도 자리 로그의 「바뀔 때만」이 안 깨진다.
    func testFailureLine_쌓여도_자리_로그가_다시_적히지_않는다() {
        var text = MediaPlaceLog.line(at: ts, device: "iphone-4532",
                                      MediaPlaceRecord(kind: .audio, place: .subdir))
        for id in ["A1", "B2", "C3"] {
            text += MediaUploadLog.failureLine(at: ts, device: "iphone-4532", kind: .audio, id: id,
                                               err: "NSCocoaErrorDomain/512")
        }
        XCTAssertNil(MediaPlaceLog.appendIfChanged(existing: text, at: ts, device: "iphone-4532",
                                                   MediaPlaceRecord(kind: .audio, place: .subdir)))
    }

    // MARK: 문구 (§8) — 사용자가 고른 말. 바뀌면 이 시험이 깨져야 한다.

    func testText_진행() {
        XCTAssertEqual(MediaMigrationText.progress(moved: 12, total: 131), "자료 옮기는 중 · 12/131")
    }

    func testText_한도_완료() {
        XCTAssertEqual(MediaMigrationText.cappedDone(moved: 5), "자료 5개를 옮겼어요 · 나머지는 다음에")
    }

    func testText_받는_중은_종류마다_다르다() {
        XCTAssertEqual(MediaMigrationText.downloading(.audio), "원본 음성 받는 중…")
        XCTAssertEqual(MediaMigrationText.downloading(.photo), "원본 사진 받는 중…")
    }

    func testText_받기_실패는_원인을_안_짚는다() {
        XCTAssertEqual(MediaMigrationText.downloadFailed, "아직 못 받았어요 · 다시 시도")
    }
}
