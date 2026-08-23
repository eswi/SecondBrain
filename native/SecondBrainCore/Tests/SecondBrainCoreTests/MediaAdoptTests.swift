import XCTest
@testable import SecondBrainCore

/// **iCloud에서 받은 것을 로컬로 들여오는 규칙** (설계 §2-A C안 · 2026-08-20).
///
/// 지키는 것 둘:
/// 1. **이름만 있는 파일(dataless)을 들여오지 않는다** — 들여오면 빈 파일이 되고
///    「로컬은 바이트가 보장된 층」이라는 전제가 깨진다(§4).
/// 2. **★ 임시 이름이 「확정 파일」 필터에 절대 안 걸린다** — 걸리면 업로더가 임시 파일을
///    iCloud에 올려 **고아**를 만들고, 차집합 재계산 때문에 **지워도 또 올라간다.**
final class MediaAdoptTests: XCTestCase {

    // MARK: 들여올 것인가

    func testAdopt_로컬에_없고_iCloud에_바이트가_있으면_들여온다() {
        XCTAssertTrue(MediaAdoptJudge.shouldAdopt(localExists: false, cloudBytesPresent: true))
    }

    func testAdopt_로컬에_이미_있으면_안_한다() {
        XCTAssertFalse(MediaAdoptJudge.shouldAdopt(localExists: true, cloudBytesPresent: true))
        XCTAssertFalse(MediaAdoptJudge.shouldAdopt(localExists: true, cloudBytesPresent: false))
    }

    /// ⛔ **이름만 있는 것으로는 안 된다.** 복사하면 빈 파일이 되고, 로컬이 「바이트 보장 층」이라는
    /// 전제가 깨진다 — 그러면 §4의 찾는 순서 `[로컬, iCloud]` 자체가 무의미해진다.
    func testAdopt_이름만_있으면_안_들여온다() {
        XCTAssertFalse(MediaAdoptJudge.shouldAdopt(localExists: false, cloudBytesPresent: false))
    }

    // MARK: ★ 임시 이름 — 업로더에게 안 잡혀야 한다

    /// **이 시험이 이 파일의 존재 이유다.** `localFiles()`는 로컬 디렉터리를 **확장자로 걸러**
    /// 업로더의 차집합 왼쪽을 만든다. 임시 이름이 그 필터를 통과하면 업로더가
    /// `sb-adopting-<id>`를 id로 계산해 **고아 파일을 iCloud에 올린다.**
    func testPartName_확정파일_필터에_안_걸린다() {
        for kind in MediaKind.allCases {
            let name = MediaAdoptNaming.partName(kind: kind, name: "0321BB39.\(kind.ext)")
            XCTAssertFalse(MediaAdoptNaming.looksLikeFinalizedFile(name, kind: kind),
                           "임시 이름이 확정 파일로 보인다: \(name)")
        }
    }

    /// 대조군 — **확정 파일은 그 필터에 걸려야 한다.** 위 시험이 「아무것도 안 걸린다」로
    /// 통과하는 것을 막는다(필터가 망가져도 위가 초록이면 알 수 없다).
    func testPartName_대조군_확정파일은_걸린다() {
        XCTAssertTrue(MediaAdoptNaming.looksLikeFinalizedFile("0321BB39.m4a", kind: .audio))
        XCTAssertTrue(MediaAdoptNaming.looksLikeFinalizedFile("0321BB39.jpg", kind: .photo))
    }

    func testPartName_꼴() {
        XCTAssertEqual(MediaAdoptNaming.partName(kind: .audio, name: "AB12.m4a"), "sb-adopting-AB12.m4a.part")
        XCTAssertEqual(MediaAdoptNaming.partName(kind: .photo, name: "AB12.jpg"), "sb-adopting-AB12.jpg.part")
    }

    func testIsPartName_찌꺼기_청소가_찾는다() {
        XCTAssertTrue(MediaAdoptNaming.isPartName(MediaAdoptNaming.partName(kind: .audio, name: "AB12.m4a")))
        XCTAssertTrue(MediaAdoptNaming.isPartName(MediaAdoptNaming.partName(kind: .photo, name: "AB12.jpg")))
    }

    func testIsPartName_확정파일은_청소_대상이_아니다() {
        XCTAssertFalse(MediaAdoptNaming.isPartName("0321BB39.m4a"))
        XCTAssertFalse(MediaAdoptNaming.isPartName("0321BB39.jpg"))
    }

    /// ⚠️ 업로더의 찌꺼기 접두사(`sb-uploading-`)와 **겹치지 않는다.**
    /// 겹치면 업로더의 청소가 **iCloud 폴더에서** 도는 동안 이름 규칙이 헷갈릴 수 있고,
    /// 무엇보다 **로그를 읽을 때 어느 쪽 찌꺼기인지 못 가린다.**
    func testPrefix_업로더_찌꺼기와_안_겹친다() {
        XCTAssertNotEqual(MediaAdoptNaming.prefix, "sb-uploading-")
        XCTAssertFalse(MediaAdoptNaming.prefix.hasPrefix("sb-uploading-"))
        XCTAssertFalse("sb-uploading-".hasPrefix(MediaAdoptNaming.prefix))
    }
}
