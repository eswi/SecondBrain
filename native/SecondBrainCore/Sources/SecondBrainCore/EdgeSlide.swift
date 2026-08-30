import Foundation

/// **테두리에만 붙어서 움직이는 단추의 자리 계산** — 수집 화면의 녹음 단추가 쓴다.
///
/// ## 무슨 결정인가 (2026-08-31 사용자)
/// > *"마이크를 꾹 눌러서 텍스트 박스 내에서 손으로 이동시킬 수 있도록 구현하자. 다만, 지금처럼
/// > 텍스트 박스와의 거리를 유지하면서 화면의 테두리로만 붙어서 이동하도록 하고, 우측 변을 따라
/// > 위아래로 움직이거나 하단 변을 따라 좌우로 움직일 수 있도록 제한하자.
/// > 지금 구현한 현재의 저 위치가 항상 디폴트 위치야."*
///
/// **길은 ㄴ자 하나다:** 우측 변(위아래) + 하단 변(좌우)이 **우측 하단 모서리에서 만난다.**
/// 그 모서리가 **기본 자리**이고, 이동량은 거기서 **위로**(`dy < 0`) 또는 **왼쪽으로**(`dx < 0`) 하나만 산다.
/// ⛔ **둘이 동시에 0이 아닌 자리는 없다** — 그러면 테두리에서 떨어진다.
///
/// ## ⚠️ 치수는 「글꼴 크기」가 아니라 「잰 자리」다 (계측 규칙 1·2)
/// `mic.circle.fill`을 `.font(.system(size: 65))`로 그리면 실제로 먹는 자리는 **76 x 74pt**다
/// (2026-08-31 맥미니 `measure-text.swift` 실측 · 52pt일 때는 61 x 59). **65를 넣으면 한계가 틀린다.**
/// ⚠️ **폭과 높이가 다르므로 딱지를 붙여 받는다**(`itemW`·`itemH`).
public enum EdgeSlide {

    /// 기본 자리(우측 하단 모서리)에서의 이동량. **하나는 반드시 0이다.**
    public struct Shift: Equatable, Sendable {
        public var dx: Double
        public var dy: Double
        public init(dx: Double, dy: Double) { self.dx = dx; self.dy = dy }
        public static let home = Shift(dx: 0, dy: 0)
    }

    /// 손가락이 끈 만큼을 **ㄴ자 길 위의 한 점으로** 접는다.
    ///
    /// - Parameters:
    ///   - base: 지금까지 확정된 이동량(끌기 시작 시점의 자리).
    ///   - dx, dy: 이번 끌기의 누적 이동(위로 끌면 `dy`가 음수, 왼쪽으로 끌면 `dx`가 음수).
    ///   - boxW, boxH: 단추가 놓이는 칸의 크기.
    ///   - itemW, itemH: **잰** 단추 자리(위 ⚠️).
    ///   - pad: 칸 테두리와의 거리 — **사용자가 「지금처럼 유지」라고 한 값이다.**
    /// - Returns: 두 성분 중 **하나는 0**인 이동량. 범위를 벗어나면 **끝에서 멈춘다**(고무줄 없음).
    ///
    /// **어느 변에 붙나:** *더 많이 끈 쪽*이다 — 위로 끈 양과 왼쪽으로 끈 양을 견줘 큰 쪽을 고른다.
    /// ⚠️ **같으면 우측 변(위아래)을 고른다** — 갈래를 정해 둬야 손이 떨릴 때 두 변을 왕복하지 않는다.
    public static func snap(base: Shift, dx: Double, dy: Double,
                            boxW: Double, boxH: Double,
                            itemW: Double, itemH: Double,
                            pad: Double) -> Shift {
        let up = max(0, -(base.dy + dy))          // 위로 올라간 양(양수)
        let left = max(0, -(base.dx + dx))        // 왼쪽으로 간 양(양수)
        // 갈 수 있는 최대. ⚠️ **음수가 나올 수 있다** — 단추가 칸보다 크면 그 방향으로 못 움직인다.
        let maxUp = max(0, boxH - itemH - pad * 2)
        let maxLeft = max(0, boxW - itemW - pad * 2)
        if up >= left { return Shift(dx: 0, dy: -min(up, maxUp)) }
        return Shift(dx: -min(left, maxLeft), dy: 0)
    }
}
