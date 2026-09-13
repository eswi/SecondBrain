import SwiftUI

#if os(iOS)
/// **가로에서 쓰는 세로 탭 띠** — 화면 **오른쪽 가장자리**에 선다 (2026-09-13 사용자 결정).
///
/// ## 왜 직접 그리나
/// SwiftUI `TabView`의 탭바는 **옆으로 못 옮긴다.** 아이폰 가로에서는 iOS가 그것을
/// **화면 아래쪽에 떠 있는 캡슐**로 그리고, **내용이 그 아래로 지나간다.**
/// 사용자: *"어차피 탭바 아래로 내려가면 내용이 안 보여."*
/// → **가로에서는 시스템 탭바를 숨기고**(`.toolbar(.hidden, for: .tabBar)`) 이것을 **형제로** 세운다.
///
/// ★★ **「형제로」가 핵심이다** — 덮어씌우는 것(`overlay`)이 아니라 `HStack`의 옆 칸이라
/// **내용이 띠 밑으로 갈 자리가 아예 없다.** 여백을 따로 계산해 줄 필요도 없다.
/// ⛔ **덮어씌우면 여백을 손으로 맞춰야 하고, 그 값은 회전·기기마다 어긋난다.**
///
/// ## 사용자가 고른 것 둘 (2026-09-13)
/// | 무엇 | 고른 것 | 안 고른 것 |
/// |---|---|---|
/// | **어느 가장자리** | **늘 화면 오른쪽** | 폰의 아래쪽 가장자리(돌린 방향에 따라 좌·우로 갈린다) |
/// | **눕히는 쪽** | **시계 방향 90°** — 글자 머리가 **왼쪽**, 위에서 아래로 읽는다 | 반시계 90° · 아이콘만 세우기 |
///
/// ⚠️ **아이콘도 함께 눕는다** — 띠 전체를 한 번 돌리기 때문이다(글자만 돌리면 방향이 어긋나 보인다).
///
/// ## 어떻게 돌리나
/// `rotationEffect`는 **자리 크기를 안 바꾼다.** 그래서 **돌리기 전 크기를 먼저 주고**
/// (가로 배치: 폭 = 띠의 길이, 높이 = 띠의 두께) 돌린 뒤 **가운데에 놓는다.**
/// ⛔ 순서를 바꾸면(돌리고 나서 크기를 주면) 칸이 어긋난다.
struct SideTabBar: View {
    @Binding var tab: AppTab

    /// 띠의 **두께**(가로 화면에서 가로로 차지하는 폭). 돌리기 전에는 이것이 **높이**다.
    /// 항목 하나 = 아이콘 22 + 사이 4 + 글자 ~13 + 위아래 여백 ⇒ 64면 넉넉하다.
    static let thickness: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { t in
                    item(t)
                }
            }
            // ★ **돌리기 전 크기** — 띠의 길이가 화면 높이가 된다.
            .frame(width: geo.size.height, height: Self.thickness)
            .rotationEffect(.degrees(90))          // 시계 방향(사용자 결정)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func item(_ t: AppTab) -> some View {
        let on = (tab == t)
        return Button {
            tab = t
        } label: {
            VStack(spacing: 4) {
                Image(systemName: t.icon).font(.system(size: 20))
                Text(t.title).font(.caption2)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? Palette.accent : Palette.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())             // 빈 곳을 눌러도 그 탭으로 간다
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}
#endif
