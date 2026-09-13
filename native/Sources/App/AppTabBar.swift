import SwiftUI

#if os(iOS)
/// **탭바 — 우리가 직접 그린다. 세로·가로 둘 다.** (2026-09-13 사용자 결정)
///
/// ## 어디서 왔나
/// 사용자가 **다른 앱의 탭바 스크린샷**을 주고 정했다:
/// *"탭바의 모양은 … 그 방식으로 해줘. 위치, 크기, 스타일 모두 그렇게. 그리고 **딱 그 영역이
/// 가로 모드로 바뀌더라도 물리적으로 유지**되도록 해주고, 그 영역에서 아이콘과 제목을
/// (지금 우리가 한 것처럼) 돌려줘. 색과 아이콘 갯수는 우리 것으로."*
///
/// **쟀다**(참고 스크린샷 · 같은 기기 402x874pt · `measure-ui.swift` @3x):
/// | 무엇 | 값 |
/// |---|---|
/// | 띠 윗단 | **780.7pt** → **띠 전체 93.3pt**(홈 인디케이터 자리 포함) |
/// | 내용 높이 | **≈59pt** (위 여백 16.6 + 아이콘 22 + 사이 ≈11 + 글자 10) |
/// | 아이콘 | **≈22pt** 높이 → `.system(size: 24)` |
/// | 글자 | 잉크 10pt → **≈12pt** |
/// | 모양 | **꽉 찬 띠** — 둥근 모서리 없음 · 좌우 여백 없음 · 내용이 그 아래로 안 간다 |
///
/// ⛔ **옛 꼴(지우지 않고 적어 둔다 · 반나절 갔다): 떠 있는 캡슐**
/// (`Capsule()` + `.regularMaterial` + 사방 21pt 여백 · 세로 시스템 탭바를 재서 옮긴 값).
/// **사용자가 참고 스크린샷으로 바꿨다** — ⚠️ **「안 됐다」가 아니라 「뜻이 아니다」**이므로
/// **되살리지 말 것**(기록 규칙 9의 셋째 갈래).
///
/// ## 「물리적으로 유지」가 뜻하는 것
/// 띠는 **기기의 아래쪽 가장자리**에 붙어 있다. 폰을 돌리면 그 가장자리가 **화면의 오른쪽**이 되므로
/// 띠도 오른쪽으로 간다 — **자리가 옮겨가는 것이 아니라 그대로 있는 것이다.**
/// 두께도 같은 값(**93pt**)을 쓴다. ⚠️ 그래서 **가로에서 안전영역을 넘어 화면 끝까지 간다** —
/// 안 그러면 안전영역(62pt)만큼 더해져 155pt가 된다.
///
/// ## 항목은 두 방향 다 **똑바로 선다**
/// 아이콘 위, 이름 아래. 가로에서는 그 묶음이 **세로로 쌓인다**(2026-09-13 사용자 결정 ·
/// 「각각 반시계 90°」 = 결국 안 돌리는 것). ⛔ **돌리지 말 것** — 한 번 돌렸다가 반려됐다.
struct AppTabBar: View {
    enum Axis { case horizontal, vertical }

    @Binding var tab: AppTab
    let axis: Axis

    /// 내용이 차지하는 두께(안전영역 제외) — 세로에서 쓴다. 실측 59pt.
    static let content: CGFloat = 59
    /// 띠 전체(안전영역 포함) — **가로에서 이 폭을 쓴다.** 실측 93.3pt.
    static let strip: CGFloat = 93

    var body: some View {
        Group {
            if axis == .horizontal {
                HStack(spacing: 0) { items }
            } else {
                VStack(spacing: 0) { items }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: axis == .horizontal ? .top : .leading) {
            // 안쪽 가장자리의 가는 선 — 참고 스크린샷의 그 경계.
            Palette.border.frame(
                width: axis == .horizontal ? nil : 0.5,
                height: axis == .horizontal ? 0.5 : nil)
        }
    }

    @ViewBuilder private var items: some View {
        ForEach(AppTab.allCases, id: \.self) { t in
            item(t)
        }
    }

    private func item(_ t: AppTab) -> some View {
        let on = (tab == t)
        return Button {
            tab = t
        } label: {
            VStack(spacing: 8) {                       // 실측 ≈11 − 글자 상단 여백 ≈ 8
                Image(systemName: t.icon).font(.system(size: 24))
                Text(t.title).font(.system(size: 12))
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(on ? Palette.accent : Palette.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())                 // 빈 곳을 눌러도 그 탭으로 간다
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}
#endif
