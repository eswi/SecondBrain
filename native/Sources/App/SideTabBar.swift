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
/// ## ★★ 항목은 **똑바로 선다** — 띠만 세로다 (2026-09-13 폰 판정에서 뒤집혔다)
///
/// 사용자: *"아이콘을 세로 보기일 때의 방향으로 돌리고, 글자도 가로모드 기준 **아이콘 아래**에 달면서
/// **좌에서 우로** 글자가 표시되게 해줘. 한마디로 아이콘/제목 한 묶음씩을 모두 각각
/// **시계 반대방향으로 90도** 돌려야 해."*
///
/// ⛔ **옛 꼴(지우지 않고 적어 둔다 · 반나절도 못 갔다):** 띠 전체를 **시계 방향 90°**로 돌렸다.
/// 그러면 **아이콘까지 누워** 쟁반·보관함이 옆으로 서고, 글자는 **위에서 아래로** 읽혔다.
/// **폰에서 반려됐다** — *"아이콘 방향과 글자 방향이 모두 틀렸어."*
/// ⚠️ **자리와 범위는 그때 통과했다**(ⓐ 누르는 자리 · ⓑ 내용이 안 물림) — **틀린 것은 방향 하나**다.
///
/// ★ **「각각 반시계 90°」는 결국 「안 돌린다」와 같다** — 띠를 +90° 돌리고 항목마다 −90°를 되돌리면
/// 남는 것은 **똑바로 선 항목을 세로로 쌓은 것**이다. 그래서 **회전을 아예 걷어냈다**(`VStack`).
/// ⛔ **두 번 돌려서 만들지 말 것** — 같은 그림인데 자리 계산만 어려워지고 누르는 자리가 위태로워진다.
///
/// ## 폭은 재서 정했다
/// 글자가 **가로로 눕지 않고 그대로** 놓이므로 **가장 긴 이름이 폭을 정한다.**
/// `measure-text.swift text` 실측(11pt = `caption2`):
/// **살아있는 기억 60.3** · 새로운 기억 50.8 · 보관된 기억 50.8 · 검색 19.1 · 설정 19.1.
/// → **60.3 + 좌우 여백 = 76pt.** ⚠️ 글자 크기 설정을 키우면 더 넓어지므로 `minimumScaleFactor`로 받는다.
/// ⛔ **옛 값 64pt는 「누운 글자」 기준이었다** — 그때는 글자 길이가 **띠의 길이 쪽**으로 갔다.
struct SideTabBar: View {
    @Binding var tab: AppTab

    /// 띠의 **두께**(가로 화면에서 가로로 차지하는 폭). **가장 긴 이름 60.3pt + 좌우 여백.**
    static let thickness: CGFloat = 76

    var body: some View {
        VStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { t in
                item(t)
            }
        }
        .frame(maxHeight: .infinity)      // 다섯이 높이를 고르게 나눠 갖는다(세로 탭바와 같은 성질)
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
            .contentShape(Rectangle())    // 빈 곳을 눌러도 그 탭으로 간다
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}
#endif
