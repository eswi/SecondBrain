import XCTest
@testable import SecondBrainCore

/// **자료 세 갈래 판정** (설계 `docs/native/media-icloud-design.md` §4 · 2026-08-19).
///
/// 지키는 것 하나: **「아직 안 받았다」와 「어디에도 없다」가 절대 뭉쳐지지 않는다.**
/// 뭉치면 파일은 iCloud에 그대로 있는데 사람은 그것을 알 방법이 없다 — `FolderLink`가 세운 원칙과 같다.
final class MediaAvailabilityTests: XCTestCase {

    private func judge(local: Bool = false, name: Bool = false, bytes: Bool = false) -> MediaAvailability {
        MediaAvailabilityJudge.status(localExists: local, cloudNameExists: name, cloudBytesPresent: bytes)
    }

    // MARK: 세 상태

    func testHere_로컬에_있으면_iCloud를_볼_것도_없다() {
        XCTAssertEqual(judge(local: true), .here)
        XCTAssertEqual(judge(local: true, name: false, bytes: false), .here)
    }

    func testHere_로컬에_없어도_iCloud가_내려와_있으면() {
        XCTAssertEqual(judge(local: false, name: true, bytes: true), .here)
    }

    /// **★ §0-B에서 쟀던 함정.** iCloud 파일은 `fileExists` = true인데 바이트가 0일 수 있다.
    /// 이름만 있는 것을 `.here`로 읽으면 **재생 버튼을 눌렀는데 아무 일도 안 난다.**
    func testNotDownloaded_이름만_있으면_여기_있다가_아니다() {
        XCTAssertEqual(judge(local: false, name: true, bytes: false), .notDownloaded)
        XCTAssertNotEqual(judge(local: false, name: true, bytes: false), .here)
    }

    func testAbsent_어디에도_없다() {
        XCTAssertEqual(judge(), .absent)
    }

    /// **이 둘이 갈리는 것이 이번 단계의 목적이다.** 옛 판정(URL 아니면 nil)은 둘을 같게 만들었다.
    func testNotDownloaded와_Absent가_절대_같지_않다() {
        XCTAssertNotEqual(judge(name: true), judge(name: false))
    }

    // MARK: 어긋난 입력

    /// 바이트가 있다는데 이름이 없다는 어긋난 입력 — **바이트 쪽을 믿는다.**
    /// 볼 수 있는 것을 못 본다고 말하지 않는다(그 방향의 거짓말이 더 나쁘다).
    func testBytes가_이름보다_우선한다() {
        XCTAssertEqual(judge(local: false, name: false, bytes: true), .here)
    }

    /// 로컬이 있으면 iCloud가 어떤 상태든 `.here`다 — **로컬이 바이트 보장 층**(§4·§5).
    func testLocal이_있으면_iCloud_상태와_무관하다() {
        for name in [true, false] {
            for bytes in [true, false] {
                XCTAssertEqual(judge(local: true, name: name, bytes: bytes), .here,
                               "name=\(name) bytes=\(bytes)")
            }
        }
    }
}
