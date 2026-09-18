import SwiftUI

/// **「새로운 기억」 우측 가장자리의 `#` 버튼** (2026-09-18 사용자 지시 · 정본 = `docs/native/edge-handle-design.md`).
///
/// 사용자: *"'새로운 기억' 화면에서 버튼 하나 달아줘. 첨부한 이미지처럼 해주면 되고, 이 버튼을 우측으로 스와잎하면
/// 우측으로 숨으면서 버튼의 곡선 부분 만큼만 보여주고, 그걸 터치하거나 좌측으로 스와잎하면 다시 나타나게 해줘.
/// 나타난 후에 터치하면 무슨 일이 생기는지는 다음 단계에서 결정해줄께. … 버튼이 우측 화면으로 들어가면, 지금은 '>>' 으로
/// 그려져 있는 모양만 나타나게 해주고 방향도 <<로 해줘. 버튼의 색깔은 첨부 이미지 색깔에 관계없이 네가 SecondBrain 전체
/// 분위기에 맞게 바꿔줘."*
///
/// ## 꼴
/// 화면 오른쪽 가장자리에 **붙은 반(半)알약** — 왼쪽만 둥글고 오른쪽은 화면 밖으로 잘린 꼴(첨부 이미지의 형태).
/// | 상태 | 보이는 것 | 폭 |
/// |---|---|---|
/// | **펼침**(`tucked == false`) | `#` + `»` | `expandedWidth` 전부 |
/// | **접힘**(`tucked == true`) | `«` 하나 | **곡선 부분만** = `peekWidth`(= 반지름 + 여유 4pt) |
///
/// ## 동작 (사용자가 정한 것 · 그대로)
/// - **오른쪽으로 끌면 접힌다** · **왼쪽으로 끌거나 접힌 것을 누르면 펼쳐진다.**
/// - ⏸ **펼친 채 누르면 = 아직 없다**(`onTap`은 비어 있다) — *"다음 단계에서 결정"*. ⛔ **짐작해 채우지 말 것.**
/// - 접힘 상태는 **기기에 남는다**(`@AppStorage`) — 숨긴 것이 앱을 다시 켤 때 되살아나면 매번 다시 숨겨야 한다(Claude 판단 · 사용자가 뒤집을 수 있다).
///
/// ## 색 (Claude가 골랐다 — 사용자가 맡겼다)
/// 첨부 이미지는 흰 유리였다. 이 앱은 어두운 팔레트라 **카드 바탕(`surface2`) + hairline(`border`)** 위에
/// **`#`만 강조색(`accent`)**, 화살표는 `textSecondary`. 「카드 하나가 가장자리에 물려 있다」로 읽히게 했다.
///
/// ## 어디에 얹나
/// `InboxView`의 **루트 `VStack`에 `.overlay(alignment: .trailing)`** — 상세로 밀려 들어가면 그 화면이 덮으므로
/// 「새로운 기억」에서만 보인다. 다른 탭에는 없다(사용자가 이 화면만 말했다).
struct EdgeHandle: View {
    @Binding var tucked: Bool
    /// 펼친 채 눌렀을 때 — **지금은 아무것도 안 한다**(다음 단계 · 사용자 결정 대기).
    var onTap: () -> Void = {}

    private let height: CGFloat = 52
    private var radius: CGFloat { height / 2 }
    private let expandedWidth: CGFloat = 92
    /// 접혔을 때 보이는 폭 — **곡선 부분(반지름)만** + 4pt(화살표가 곡선에 물리지 않게).
    private var peekWidth: CGFloat { radius + 4 }

    @GestureState private var dragX: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius,
                                   bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
                .fill(Palette.surface2)
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius,
                                           bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
                        .strokeBorder(Palette.border)
                )
                .shadow(color: .black.opacity(0.35), radius: 10, x: -2, y: 4)
            if tucked {
                Image(systemName: "chevron.left.2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: peekWidth, height: height)   // 곡선 부분 한가운데
            } else {
                HStack(spacing: 10) {
                    Text("#").font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.accent)
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.leading, 20)
                .frame(height: height)
            }
        }
        .frame(width: expandedWidth, height: height)
        .contentShape(Rectangle())
        // 접히면 왼쪽 곡선 부분만 남기고 화면 밖으로 — 끄는 동안은 손가락을 따라간다(경계 안에서만).
        .offset(x: min(max(baseOffset + dragX, 0), expandedWidth - peekWidth))
        .onTapGesture {
            if tucked { withAnimation(spring) { tucked = false } } else { onTap() }
        }
        .gesture(
            DragGesture(minimumDistance: 8)
                .updating($dragX) { v, st, _ in st = v.translation.width }
                .onEnded { v in
                    // 오른쪽으로 끌면 접힘 · 왼쪽으로 끌면 펼침. 짧은 끌기(20pt 미만)는 무시한다.
                    if v.translation.width > 20 { withAnimation(spring) { tucked = true } }
                    else if v.translation.width < -20 { withAnimation(spring) { tucked = false } }
                }
        )
        .animation(spring, value: tucked)
    }

    private var baseOffset: CGFloat { tucked ? expandedWidth - peekWidth : 0 }
    private var spring: Animation { .spring(response: 0.32, dampingFraction: 0.82) }
}
