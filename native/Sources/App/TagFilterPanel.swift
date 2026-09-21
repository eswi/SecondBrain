import SwiftUI
import SecondBrainCore

/// **해시태그 필터 — 손잡이와 패널** (2026-09-22 사용자 결정 · 정본 = `docs/native/tag-filter-design.md`).
///
/// 목록 영역에 얹는다. 닫혀 있으면 `EdgeHandle`(누르면 열림), 열려 있으면 `TagFilterPanel`이 **손잡이의 세로 자리에서 왼쪽으로** 펼쳐진다.
/// 네 화면(새로운 기억 · 검색 · 살아있는 기억 · 보관된 기억)이 각자의 `TagFilter`·열림 상태를 물려 쓴다 — 거르는 대상은 각 화면이 정한다.
///
/// - `available` = **필터 걸기 전** 그 화면 목록의 태그(설계 §2 3번). 화면이 `TagFilter.available(in:)`로 뽑아 넘긴다.
/// - 닫아도 필터는 남는다(§2 9번) — 닫힌 손잡이의 `<`가 강조색이면 걸려 있는 것이다(§2 10번).
/// - 화면의 말 셋은 사용자가 정했다: **「태그 없음」 · 「역선택」 · 「닫기」**(`>`는 chevron 기호 · Claude). 패널 제목은 없다(짓지 않았다).
struct TagFilterDock: View {
    @Binding var topOffset: Double
    @Binding var filter: TagFilter
    @Binding var isOpen: Bool
    let available: [String]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isOpen {
                TagFilterPanel(topOffset: topOffset, filter: $filter, available: available) {
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

/// 패널 — 태그 칩(중복 선택) · 맨 끝 「태그 없음」 · 구분선 · 「역선택」 토글 · 오른쪽 「닫기 >」.
struct TagFilterPanel: View {
    /// 손잡이의 세로 자리(음수 = 가운데) — 패널의 위 끝을 여기 맞추고, 영역을 넘으면 안으로 밀어 넣는다.
    let topOffset: Double
    @Binding var filter: TagFilter
    let available: [String]
    let onClose: () -> Void

    @State private var panelHeight: CGFloat = 0
    /// 칩 글자 = 상세의 「이 분류에서 쓴 해시태그」 칩과 같은 14pt(글자 크기 설정을 따라간다).
    @ScaledMetric(relativeTo: .body) private var chipSize: CGFloat = 14
    private let radius: CGFloat = 14   // 손잡이와 같은 원호

    var body: some View {
        GeometryReader { geo in
            let handleH: CGFloat = 96
            let wanted: CGFloat = topOffset < 0 ? max(0, geo.size.height - handleH) / 2 : CGFloat(topOffset)
            let top = min(max(wanted, 0), max(0, geo.size.height - panelHeight))
            let width = min(300, max(160, geo.size.width - 48))
            panel(maxChipsHeight: max(120, geo.size.height * 0.5))
                .frame(width: width)
                .background(shape.fill(Palette.surface2))
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

    private func panel(maxChipsHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 태그 칩 — 필터 전 목록의 태그 전부 + 맨 끝 「태그 없음」. 많으면 세로로 스크롤한다.
            ScrollView(.vertical, showsIndicators: false) {
                WrapLayout(hSpacing: 6, vSpacing: 6) {
                    ForEach(available, id: \.self) { t in
                        chip(HashTag.display(t), on: filter.selected.contains(t)) { filter.toggle(t) }
                    }
                    chip("태그 없음", on: filter.includesUntagged, dim: true) { filter.includesUntagged.toggle() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: maxChipsHeight)
            .fixedSize(horizontal: false, vertical: true)   // 내용만큼만 — 상한을 넘을 때만 스크롤

            Divider().overlay(Palette.border)   // 사용자: "수평 seperator를 하나"

            HStack(spacing: 8) {
                // 「역선택」 — 토글 버튼(켜지면 칩과 같은 꼴로 채워진다).
                chip("역선택", on: filter.inverted) { filter.inverted.toggle() }
                Spacer(minLength: 0)
                // 「닫기 >」 — 패널만 감춘다(필터는 그대로 · 설계 §2 9번).
                Button(action: onClose) {
                    HStack(spacing: 3) {
                        Text("닫기").font(.system(size: chipSize, weight: .semibold))
                        Image(systemName: "chevron.right").font(.system(size: chipSize - 2, weight: .semibold))
                    }
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    /// 칩 — 꺼짐 = 원문 색 글자 + `border` 테두리(상세의 「이 분류에서 쓴 해시태그」와 같다) · 켜짐 = 강조색 바탕 + 바탕색 글자(분류 칩의 켜진 꼴 규칙).
    private func chip(_ label: String, on: Bool, dim: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: chipSize, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Palette.bg : (dim ? Palette.textSecondary : Palette.textPrimary))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background {
                    if on { Capsule().fill(Palette.accent) } else { Capsule().stroke(Palette.border) }
                }
        }
        .buttonStyle(.plain)
    }
}
