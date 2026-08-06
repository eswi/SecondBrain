import XCTest
@testable import SecondBrainCore

/// **폴더 연결 상태 판정 (사양서 §0-A-1, 2026-08-06).**
/// 원칙: **연결이 끊긴 것과 비어 있는 것을 절대 같게 보이지 않는다.**
///
/// 이 판정이 없던 동안 조용히 비는 길이 다섯인데 화면에선 전부 "새 기억이 없어요"였다 —
/// 사용자 눈에는 **기억 전체가 사라진 것**이다. 그 다섯 갈래를 여기서 못박는다.
final class FolderLinkTests: XCTestCase {

    /// 정상(전부 통과)을 기본값으로 두고 한 가지씩만 무너뜨려 본다 — 무엇이 판정을 바꾸는지가 드러나게.
    private func judge(bookmark: Bool = true, resolved: Bool = true, access: Bool = true,
                       listed: Bool = true, files: Int = 3, readable: Int = 3) -> FolderLink {
        FolderLinkJudge.status(bookmarkExists: bookmark, resolved: resolved, accessGranted: access,
                               directoryListed: listed, fragmentFiles: files, readableFiles: readable)
    }

    // MARK: 다섯 상태

    func testNotChosen_noBookmark() {
        XCTAssertEqual(judge(bookmark: false), .notChosen)
        // 북마크가 없으면 뒤의 사실은 볼 것도 없다.
        XCTAssertEqual(judge(bookmark: false, resolved: false, access: false, listed: false,
                             files: 0, readable: 0), .notChosen)
    }

    /// **막힌 자리가 어디든 "못 연다" 하나다** — 사람이 할 일이 같다(다시 연결).
    func testUnreachable_anyBlockedStep() {
        XCTAssertEqual(judge(resolved: false), .unreachable)   // 북마크 해소 실패
        XCTAssertEqual(judge(access: false), .unreachable)     // 접근 거부 — 옛 코드는 이걸 보지도 않았다
        XCTAssertEqual(judge(listed: false), .unreachable)     // 목록 읽기 실패
    }

    /// **★ 이 갈래가 이번 작업의 핵심.** 파일은 있는데 하나도 못 읽었다 = iCloud에서 아직 안 내려옴.
    /// 새 기기에서 가장 흔한 경로이고, 판정이 없으면 "비었다"와 구분되지 않는다.
    func testDownloading_filesPresentButNoneReadable() {
        XCTAssertEqual(judge(files: 5, readable: 0), .downloading)
    }

    /// 폴더는 열렸는데 조각 파일이 0개. **사고가 아니라 정상 상태다**(새 폴더를 막 골랐을 때).
    func testEmpty_isNotAnAccident() {
        XCTAssertEqual(judge(files: 0, readable: 0), .empty)
    }

    func testOK() {
        XCTAssertEqual(judge(files: 3, readable: 3), .ok(files: 3))
    }

    // MARK: ★ 갈라져야 하는 두 쌍 — 여기서 헷갈리면 이번 작업이 무의미하다

    /// **"비었다"와 "못 연다"가 갈린다.** 옛 코드에선 둘 다 빈 배열이라 같은 화면이었다.
    func testEmptyAndUnreachableAreNeverTheSame() {
        XCTAssertNotEqual(judge(files: 0, readable: 0), judge(resolved: false))
        XCTAssertEqual(judge(files: 0, readable: 0), .empty)
        XCTAssertEqual(judge(resolved: false), .unreachable)
    }

    /// **"비었다"와 "받는 중"도 갈린다.** 파일이 목록에 잡혔느냐가 그 둘을 가른다.
    func testEmptyAndDownloadingAreNeverTheSame() {
        XCTAssertEqual(judge(files: 0, readable: 0), .empty)        // 목록에 아무것도 없다
        XCTAssertEqual(judge(files: 5, readable: 0), .downloading)  // 있는데 못 읽었다
    }

    /// 일부만 읽힌 것은 **`ok`** 다 — 앱을 쓸 수 있고 나머지는 다음 로드에서 채워진다.
    /// 대신 `files`가 평소보다 **작은 수로 보이는 것 자체가 신호**가 된다(설정이 이 수를 보여준다).
    func testPartiallyReadable_isUsableAndTheNumberIsTheSignal() {
        XCTAssertEqual(judge(files: 5, readable: 2), .ok(files: 2))
    }

    // MARK: 화면이 무엇을 하는지

    /// 안내 화면은 **정상일 때만** 안 뜬다. 나머지 넷은 전부 뜬다 — "못 연다"·"받는 중"이
    /// 온보딩 화면으로 **오게 하는 것**이 이번 변경의 절반이다(지금은 도달조차 안 했다).
    func testGuidanceShownForEveryStateButOK() {
        XCTAssertTrue(FolderLink.notChosen.needsGuidance)
        XCTAssertTrue(FolderLink.unreachable.needsGuidance)
        XCTAssertTrue(FolderLink.downloading.needsGuidance)
        XCTAssertTrue(FolderLink.empty.needsGuidance)
        XCTAssertFalse(FolderLink.ok(files: 1).needsGuidance)
    }

    /// **★ "비었다"에서는 담을 수 있어야 한다.** 그 화면이 *"아래 마이크를 눌러 말하거나 적어보세요"* 라고
    /// 말하는데 마이크가 없으면 **화면이 거짓말을 한다.** "안내 화면인가" 하나로 마이크를 숨기면 이 모순이 난다.
    func testCanCapture_emptyMustAllowIt() {
        XCTAssertTrue(FolderLink.empty.canCapture, "비었다 화면의 안내가 거짓이 된다")
        XCTAssertTrue(FolderLink.ok(files: 2).canCapture)
        // 쓸 곳이 없거나(못 연다·안 골랐다) 쓰면 위험하다(받는 중 — 아직 안 온 것 위에 쌓게 된다).
        XCTAssertFalse(FolderLink.notChosen.canCapture)
        XCTAssertFalse(FolderLink.unreachable.canCapture)
        XCTAssertFalse(FolderLink.downloading.canCapture)
    }

    /// "폴더 선택"과 "폴더 변경"을 가르는 값 — 안 고른 것만 아직 연결 전이다.
    func testIsLinked() {
        XCTAssertFalse(FolderLink.notChosen.isLinked)
        for s in [FolderLink.unreachable, .downloading, .empty, .ok(files: 1)] {
            XCTAssertTrue(s.isLinked, "\(s)")
        }
    }

    // MARK: ★ 회귀선 — 정상 상태에서 아무것도 안 바뀐다

    /// 이번 변경의 무영향 조건. 정상이면 안내를 안 띄우고 연결된 것으로 본다 —
    /// 옛 `needsFolder == false`와 같은 결론이어야 한다.
    func testNormalStateUnchanged() {
        let s = judge()
        XCTAssertEqual(s, .ok(files: 3))
        XCTAssertFalse(s.needsGuidance)   // 옛 needsFolder = false 와 같은 자리
        XCTAssertTrue(s.isLinked)
    }

    /// **빈 폴더를 사고로 취급하지 않는다** — 과잉 경보를 막는 것이 이 작업의 절반이다.
    /// 안내는 띄우되 "못 연다"와 **같은 값이 아니어야** 한다(문구가 갈리는 근거).
    func testEmptyIsGuidedButNotAlarming() {
        let s = judge(files: 0, readable: 0)
        XCTAssertTrue(s.needsGuidance)
        XCTAssertTrue(s.isLinked)          // 연결은 돼 있다 — 끊긴 게 아니다
        XCTAssertNotEqual(s, .unreachable)
    }
}
