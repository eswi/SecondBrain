import SwiftUI

/// **「새로운 기억」 우측 가장자리 버튼** (2026-09-18 사용자 지시 · 정본 = `docs/native/edge-handle-design.md`).
///
/// ## 2026-09-21 사용자 지시로 바뀐 것 (설계 §5 · 말 그대로 있다)
/// - **펼침 꼴(`#` + `»`)을 없앴다** — *"눌렀을 때 나타나는 버튼은 새로 디자인할 것이니 일단 없애자."*
///   그래서 **좌우로 끌어 접고 펼치는 것도 없다**(접힐 것이 없다). 지금은 **가장자리에 물린 손잡이 하나**다.
/// - **눌러서 위아래로만 옮긴다** — *"이동 방향은 위/아래로만 … 최상단 제목 영역으로 침범하지 않도록 그리고 최하단 탭바를
///   침범하지 않도록."* → 이 뷰는 **얹힌 영역의 높이 안에서만** 움직인다. 그 영역 = `InboxView`의 `content`(머리줄 아래 · 탭바 위).
/// - ✅ **모양·크기 = 사용자 스크린샷(09-21 17:0x · 홈 화면 오른쪽 가장자리의 손잡이)대로** — 세로로 긴 둥근 네모(왼쪽 모서리만 둥글다) ·
///   **폭 24 · 높이 92 · 반지름 14** · 가운데 `‹` 하나(`chevron.left` 22pt). 값은 스크린샷을 표시 배율(0.437pt/px)로 환산한 **추정**이다 —
///   폰에서 나란히 보고 사용자가 다듬는다.
/// - 위치는 **기기에 남는다**(`@AppStorage` · 음수 = 아직 안 옮김 → 세로 가운데).
///
/// ## 옛 꼴 (지우지 않는다 · 09-18 `823beae`)
/// `#`+`»` 반알약 → 오른쪽으로 끌면 곡선 부분만 남고 `«` → 누르거나 왼쪽으로 끌면 펼침. **동작했고 사용자가 거둔 것**이다 —
/// 「안 됐다」가 아니라 **「새로 디자인한다」**(기록 규칙 9의 셋째 갈래 ②). ⛔ **되살리지 말 것.**
///
/// ## 색 (Claude가 골랐다 — 09-18 사용자가 맡겼다)
/// 카드 바탕(`surface2`) + hairline(`border`) · 화살표 `textSecondary`.
struct EdgeHandle: View {
    /// 얹힌 영역의 **위에서부터의 거리**(pt). **음수 = 아직 안 옮김** → 세로 가운데에 둔다.
    @Binding var topOffset: Double

    /// 스크린샷에서 읽은 치수(추정 · 머리주석). 옛 값(09-18 접힌 꼴): 높이 52 · 반지름 26 · 폭 30.
    private let height: CGFloat = 92
    private let radius: CGFloat = 14
    private let width: CGFloat = 24

    @GestureState private var dragY: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let maxTop = max(0, geo.size.height - height)
            let base: CGFloat = topOffset < 0 ? maxTop / 2 : CGFloat(topOffset)
            let top = min(max(base + dragY, 0), maxTop)   // 제목 아래 ~ 탭바 위 — 영역 밖으로 못 나간다
            shape
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .offset(y: top)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .updating($dragY) { v, st, _ in st = v.translation.height }   // 세로만 읽는다
                        .onEnded { v in topOffset = Double(min(max(base + v.translation.height, 0), maxTop)) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private var shape: some View {
        ZStack {
            let r = UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius,
                                           bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
            // 스크린샷은 어두운 반투명 바탕에 테두리가 없다 — 이 앱 팔레트로는 `surface2`(살짝 비치게) · hairline은 옅게만.
            r.fill(Palette.surface2.opacity(0.92))
                .overlay(r.strokeBorder(Palette.border.opacity(0.6)))
                .shadow(color: .black.opacity(0.3), radius: 8, x: -2, y: 3)
            Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
        }
    }
}
