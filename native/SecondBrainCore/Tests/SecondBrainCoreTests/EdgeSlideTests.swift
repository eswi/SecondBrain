import XCTest
@testable import SecondBrainCore

/// **결정을 지키는 시험** — 「녹음 단추는 테두리에만 붙어서 움직인다」(2026-08-31 사용자 결정).
///
/// ① **무슨 결정인가:** *"텍스트 박스와의 거리를 유지하면서 화면의 테두리로만 붙어서 이동하도록 하고,
///    우측 변을 따라 위아래로 움직이거나 하단 변을 따라 좌우로 움직일 수 있도록 제한하자.
///    지금 구현한 현재의 저 위치가 항상 디폴트 위치야."* 정본 = `EdgeSlide` 머리주석.
/// ② **사실:** 길은 **ㄴ자 하나**이고 두 성분 중 **하나는 반드시 0**이다(그러지 않으면 테두리에서 떨어진다).
///    끝에서는 **멈춘다**(고무줄 없음). 단추가 칸보다 크면 그 방향으로 **못 움직인다**.
/// ③ **깨지면 무엇을 의심하나:** 구현이 아니라 **누군가 「자유 이동」으로 넓혔거나**(대각선이 생긴다)
///    **치수를 「잰 자리」가 아니라 「글꼴 크기」로 넘겼다**(65 vs 실측 76x74)를 의심한다.
final class EdgeSlideTests: XCTestCase {

    // 수집 화면의 실제 값 — 단추는 **잰 자리**로 넣는다(글꼴 65가 아니라 76 x 74).
    private let boxW = 370.0, boxH = 200.0
    private let itemW = 76.0, itemH = 74.0
    private let pad = 10.0

    private func snap(base: EdgeSlide.Shift = .home, _ dx: Double, _ dy: Double,
                      boxH: Double? = nil) -> EdgeSlide.Shift {
        EdgeSlide.snap(base: base, dx: dx, dy: dy,
                       boxW: boxW, boxH: boxH ?? self.boxH,
                       itemW: itemW, itemH: itemH, pad: pad)
    }

    /// 기본 자리는 **우측 하단 모서리**(이동량 0,0).
    func testHomeIsBottomTrailing() {
        XCTAssertEqual(snap(0, 0), .home)
    }

    /// ⛔ **대각선은 없다** — 두 성분 중 하나는 늘 0이다.
    func testNeverLeavesTheEdge() {
        for (dx, dy) in [(-40.0, -40.0), (-5.0, -80.0), (-90.0, -3.0), (-1.0, -1.0)] {
            let s = snap(dx, dy)
            XCTAssertTrue(s.dx == 0 || s.dy == 0, "테두리에서 떨어졌다: \(s)")
        }
    }

    /// 위로 더 많이 끌면 **우측 변**을 따라 올라간다.
    func testDragUpFollowsRightEdge() {
        let s = snap(-10, -60)
        XCTAssertEqual(s.dx, 0)
        XCTAssertEqual(s.dy, -60, accuracy: 0.001)
    }

    /// 왼쪽으로 더 많이 끌면 **하단 변**을 따라 간다.
    func testDragLeftFollowsBottomEdge() {
        let s = snap(-120, -10)
        XCTAssertEqual(s.dy, 0)
        XCTAssertEqual(s.dx, -120, accuracy: 0.001)
    }

    /// 같으면 **우측 변**을 고른다 — 갈래를 정해 둬야 손이 떨릴 때 두 변을 왕복하지 않는다.
    func testTieGoesToRightEdge() {
        let s = snap(-30, -30)
        XCTAssertEqual(s.dx, 0)
        XCTAssertEqual(s.dy, -30, accuracy: 0.001)
    }

    /// 반대 방향(아래·오른쪽)으로 끌어도 **모서리를 넘지 않는다.**
    func testCannotGoPastHome() {
        XCTAssertEqual(snap(50, 50), .home)
    }

    /// 끝에서 **멈춘다** — 고무줄처럼 더 가지 않는다.
    func testClampsAtFarEnd() {
        let maxUp = boxH - itemH - pad * 2          // 200 - 74 - 20 = 106
        XCTAssertEqual(snap(0, -9999).dy, -maxUp, accuracy: 0.001)
        let maxLeft = boxW - itemW - pad * 2        // 370 - 76 - 20 = 274
        XCTAssertEqual(snap(-9999, 0).dx, -maxLeft, accuracy: 0.001)
    }

    /// ★★ **단추가 칸보다 크면 그 방향으로 못 움직인다 — 실제 값이 그렇다.**
    /// 수집 화면 텍스트 칸의 **시작 높이는 80pt**이고 단추는 **74pt + 여백 20pt**를 먹는다
    /// → **위로 갈 자리가 없다**(80 − 74 − 20 = −14 → 0). **글이 늘어 칸이 커지면 생긴다.**
    /// ⛔ **이 시험이 깨졌다면 칸의 최소 높이나 여백이 바뀐 것이다** — 그때 사용자에게 알린다.
    func testNoVerticalRoomAtDefaultBoxHeight() {
        XCTAssertEqual(snap(0, -100, boxH: 80).dy, 0, accuracy: 0.001)
        // 좌우는 넉넉하다 — 같은 칸에서 왼쪽으로는 274pt까지 간다.
        XCTAssertEqual(snap(-9999, 0, boxH: 80).dx, -274, accuracy: 0.001)
    }

    /// 이미 옮겨 둔 자리에서 이어 끌 수 있다(누적).
    func testAccumulatesFromBase() {
        let base = EdgeSlide.Shift(dx: 0, dy: -40)
        XCTAssertEqual(snap(base: base, 0, -20).dy, -60, accuracy: 0.001)
    }

    /// 하단 변에 있던 것을 위로 끌면 **우측 변으로 옮겨간다**(ㄴ자 길에서 갈래가 바뀐다).
    func testSwitchesEdgeWhenDominantAxisChanges() {
        let base = EdgeSlide.Shift(dx: -200, dy: 0)
        let s = snap(base: base, 0, -300)      // 위로 300 · 왼쪽 누적 200 → 위가 이긴다
        XCTAssertEqual(s.dx, 0)
        XCTAssertTrue(s.dy < 0)
    }
}
