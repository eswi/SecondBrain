import SwiftUI
import SecondBrainCore

/// **해시태그 필터 — 손잡이와 패널** (2026-09-22 사용자 결정 · 정본 = `docs/native/tag-filter-design.md`).
///
/// 목록 영역에 얹는다. 닫혀 있으면 `EdgeHandle`(누르면 열림), 열려 있으면 `TagFilterPanel`이 **손잡이의 세로 자리에서 왼쪽으로** 펼쳐진다.
/// 네 화면(새로운 기억 · 검색 · 살아있는 기억 · 보관된 기억)이 각자의 `TagFilter`·열림 상태를 물려 쓴다 — 거르는 대상은 각 화면이 정한다.
///
/// - `items` = **필터 걸기 전** 그 화면의 목록(설계 §2 3번). 태그 나열(`TagFilter.available`)과 제목의 숫자 셋(`counts`)을 여기서 뽑는다.
/// - 닫아도 필터는 남는다(§2 9번) — 닫힌 손잡이의 `<`가 강조색이면 걸려 있는 것이다(§2 10번).
/// - 화면의 말은 사용자가 정했다: **「태그 없음」 · 「역선택」 · 「닫기」** · 제목 **「전체 N · 선택 N · 그 외 N」**(2026-09-22 맥북 · 후보 넷 중 사용자가 골랐다).
struct TagFilterDock: View {
    @Binding var topOffset: Double
    @Binding var filter: TagFilter
    @Binding var isOpen: Bool
    let items: [ResolvedItem]

    var body: some View {
        let available = TagFilter.available(in: items)
        ZStack(alignment: .topTrailing) {
            if isOpen {
                TagFilterPanel(topOffset: topOffset, filter: $filter, items: items, available: available) {
                    isOpen = false
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                EdgeHandle(topOffset: $topOffset, active: filter.pruned(to: available).isActive) { isOpen = true }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: isOpen)
    }
}

/// 패널 — **세 영역**(2026-09-22 사용자: *"영역 구분과 바탕색 구분이 필요해. 지금은 너무 어둡고"*):
/// ① 위 **제목 띠**(숫자 셋) · ② 가운데 **칩 영역**(태그 칩 · 맨 끝 「태그 없음」) · ③ 아래 **띠**(「역선택」 토글 · 오른쪽 「닫기 >」).
/// 띠 둘은 같은 바탕(`barFill`), 칩 영역은 그보다 어두운 바탕(`bodyFill`) — 셋이 색으로 갈린다. 구분선(사용자 §2 6번)은 ②와 ③ 사이에 그대로 있다.
///
/// ## 폭 = 화면의 45% (2026-09-22 사용자 · 설계 §7-1에 계산)
/// 43~47%를 1pt씩 밟아 「한 줄에 들어가는 글자 수」를 셌다 — **폭을 1~2% 움직여서는 글자 수가 안 변하고, 칩의 여백을 줄여야 변한다.**
/// 그래서 폭은 45%로 두고 **칩 좌우 여백 9 → 7 · 칩 사이 6 → 4 · 패널 안쪽 여백 12 → 10**으로 줄였다(2자 태그가 한 줄에 2개 → 3개 · 4자 태그 1개 → 2개).
///
/// ## 칩은 전부 바탕이 있다 (2026-09-22 사용자: *"모든 해시태그들은 바탕색이 있는 것으로"*)
/// 고른 것 = 강조색 바탕 + 바탕색 글자(그대로) · **안 고른 것 = 회색 바탕**(`chipFill` · 글자색과 패널 바탕의 중간 · 글자 대비 6.5:1) — 태그 안에 빈칸이 있어도 태그 단위로 보인다.
struct TagFilterPanel: View {
    /// 손잡이의 세로 자리(음수 = 가운데) — 패널의 위 끝을 여기 맞추고, 영역을 넘으면 안으로 밀어 넣는다.
    let topOffset: Double
    @Binding var filter: TagFilter
    let items: [ResolvedItem]
    let available: [String]
    let onClose: () -> Void

    @State private var panelHeight: CGFloat = 0
    /// 칩 글자 = 상세의 「이 분류에서 쓴 해시태그」 칩과 같은 14pt(글자 크기 설정을 따라간다).
    @ScaledMetric(relativeTo: .body) private var chipSize: CGFloat = 14
    /// 제목 글자 = **「닫기」와 같은 크기**(`chipSize` 14pt · 2026-09-22 사용자: *"제목쪽 크기도 닫기 크기에 맞춰봐줘"* — 13pt였다).
    /// 14pt semibold로 「전체 94 · 선택 12 · 그 외 82」 = 162.0pt(macOS 실측 · 3pt쯤 크게 읽는 도구) vs 안쪽 161 — 아슬해서 넘치면 한 줄 안에서 줄인다(`minimumScaleFactor(0.8)` · 세 자리 셋 170.1도 0.8이면 든다).
    private let radius: CGFloat = 14   // 손잡이와 같은 원호
    /// 화면 폭에 대한 패널 폭 비율(사용자: "대략 45%").
    private let widthRatio: CGFloat = 0.45
    private let inset: CGFloat = 10          // 패널 안쪽 좌우 여백(옛 12)
    private let chipHPad: CGFloat = 7        // 칩 좌우 여백(옛 9)
    private let chipGap: CGFloat = 4         // 칩 사이(옛 6)

    // 색 — Claude가 골랐다(사용자가 폰에서 다듬는다). 밝기(대비)는 설계 §7-1 표.
    private let bodyFill = Color(hex: 0x302C3B)   // 칩 영역 바탕(옛 `surface2` 26232F보다 한 단 밝다)
    private let barFill  = Color(hex: 0x3E3A4B)   // 제목 띠·아래 띠 바탕(칩 영역보다 밝다)
    private let chipFill = Color(hex: 0x555064)   // 안 고른 칩 바탕(회색 · 글자와 6.5:1)

    var body: some View {
        GeometryReader { geo in
            let handleH: CGFloat = 96
            let wanted: CGFloat = topOffset < 0 ? max(0, geo.size.height - handleH) / 2 : CGFloat(topOffset)
            let top = min(max(wanted, 0), max(0, geo.size.height - panelHeight))
            let width = max(160, (geo.size.width * widthRatio).rounded())
            panel(width: width, maxChipsHeight: max(120, geo.size.height * 0.5))
                .frame(width: width)
                .background(shape.fill(bodyFill))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Palette.border))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                .offset(y: top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius,
                               bottomTrailingRadius: 0, topTrailingRadius: 0, style: .circular)
    }

    private func panel(width: CGFloat, maxChipsHeight: CGFloat) -> some View {
        let c = filter.pruned(to: available).counts(in: items)
        return VStack(alignment: .leading, spacing: 0) {
            // ① 제목 띠 — 숫자 셋(항상 보인다 · 사용자). 문구는 사용자가 골랐다(2026-09-22 맥북).
            Text("전체 \(c.total) · 선택 \(c.selected) · 그 외 \(c.rest)")
                .font(.system(size: chipSize, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, inset).padding(.vertical, 8)
                .background(barFill)

            // ② 칩 영역 — 필터 전 목록의 태그 전부 + 맨 끝 「태그 없음」. 많으면 세로로 스크롤한다.
            ScrollView(.vertical, showsIndicators: false) {
                WrapLayout(hSpacing: chipGap, vSpacing: 6) {
                    ForEach(available, id: \.self) { t in
                        chip(HashTag.display(t), on: filter.selected.contains(t)) { filter.toggle(t) }
                    }
                    chip("태그 없음", on: filter.includesUntagged, dim: true) { filter.includesUntagged.toggle() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, inset).padding(.vertical, 10)
            }
            .frame(maxHeight: maxChipsHeight)
            .fixedSize(horizontal: false, vertical: true)   // 내용만큼만 — 상한을 넘을 때만 스크롤

            Divider().overlay(Palette.border)   // 사용자: "수평 seperator를 하나"

            // ③ 아래 띠 — 「역선택」 **스위치** · 오른쪽 「닫기 >」(패널만 감춘다 · 필터는 그대로 · 설계 §2 9번).
            //    「역선택」은 칩(선택)이 아니라 **토글**이라 시스템 스위치로 그린다(2026-09-22 사용자: *"이건 선택이 아니라 토글이야"* — 칩 꼴은 뒤집혔다 · 설계 §7-4).
            //    ⛔ 첫 판(`bb02f98`)은 「닫기」가 두 줄(닫/기)로 꺾였다 — 스위치 51pt에 라벨 간격·버튼 여백을 더하니 안쪽 161을 넘었다(시뮬 스크린샷 · 설계 §7-4).
            //    → 라벨과 스위치 사이 6 · 「닫기」 좌우 여백 10 → 6 · 사이 8 → 4 · 「닫기」는 꺾이지 않게(`fixedSize`) = 36.4 + 6 + 51 + 4 + 48 ≈ 146 ≤ 161.
            HStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("역선택").font(.system(size: chipSize, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                    Toggle("역선택", isOn: $filter.inverted).labelsHidden().toggleStyle(.switch).tint(Palette.accent)
                }
                .fixedSize()
                Spacer(minLength: 0)
                Button(action: onClose) {
                    HStack(spacing: 3) {
                        Text("닫기").font(.system(size: chipSize, weight: .semibold))
                        Image(systemName: "chevron.right").font(.system(size: chipSize - 2, weight: .semibold))
                    }
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 6).padding(.vertical, 5)
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, inset).padding(.vertical, 8)
            .background(barFill)
        }
    }

    /// 칩 — 켜짐 = 강조색 바탕 + 바탕색 글자(분류 칩의 켜진 꼴 규칙) · 꺼짐 = **회색 바탕**(`chipFill`) + 원문 색 글자(「태그 없음」은 흐린 글자).
    /// *(옛 꼴 · 09-22 01:2x까지: 꺼짐 = 바탕 없이 `border` 테두리만 — 사용자가 「모든 해시태그에 바탕색」으로 바꿨다.)*
    private func chip(_ label: String, on: Bool, dim: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: chipSize, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Palette.bg : (dim ? Palette.textSecondary : Palette.textPrimary))
                .padding(.horizontal, chipHPad).padding(.vertical, 5)
                .background(Capsule().fill(on ? Palette.accent : chipFill))
        }
        .buttonStyle(.plain)
    }
}
