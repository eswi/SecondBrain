import SwiftUI
import SecondBrainCore

// MARK: - D-day 배지

struct DDayBadge: View {
    let dday: DDay

    private var text: String {
        switch dday.bucket {
        case .overdue: return "D+\(-dday.days)"   // 지남
        case .today:   return "D-DAY"
        case .future:  return "D-\(dday.days)"
        }
    }
    private var color: Color {
        switch dday.bucket {
        case .overdue: return Palette.overdue
        case .today:   return Palette.today
        case .future:  return Palette.neutral
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold)).monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: - source 아이콘 배지

struct SourceBadge: View {
    let source: String?
    var body: some View {
        Image(systemName: SourceIcon.symbol(source))
            .font(.caption2)
            .foregroundStyle(Palette.textTertiary)
    }
}

// MARK: - 종류 아이콘 (버튼 → 분류 변경 메뉴)

/// 항목의 종류를 나타내는 아이콘. 탭하면 종류 선택 메뉴가 떠서 분류를 바꾼다(엔진 재사용).
struct TypeMenuButton: View {
    let item: ResolvedItem
    let onChange: (String) -> Void

    var body: some View {
        Menu {
            ForEach(ClassRegistry.assignable) { m in    // 기본층 6 + 유연층(주차 위치) — 상세화면과 동일 집합
                Button {
                    if let k = m.key { onChange(k) }
                } label: {
                    Label(m.label, systemImage: m.symbol)
                }
                .disabled(m.key == item.type)
            }
        } label: {
            let m = ClassRegistry.meta(item.type)       // 유연층-인지 조회(주차=car). 기본층-전용이면 미분류로 폴백됨
            Image(systemName: m.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(m.color)
                .frame(width: 30, height: 30)
                .background(m.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

/// 비대화형 종류 글리프(보관함 등에서).
struct TypeGlyph: View {
    let type: String?
    var body: some View {
        let m = ClassRegistry.meta(type)                // 유연층-인지 조회(주차 포함) — TypeMenuButton과 통일
        Image(systemName: m.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(m.color)
            .frame(width: 28, height: 28)
            .background(m.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 항목 캡션(출처 · 시각 · 시점)

func itemCaption(_ it: ResolvedItem) -> String {
    var parts: [String] = []
    let dt = "\(it.date ?? "") \(it.time ?? "")".trimmingCharacters(in: .whitespaces)
    if !dt.isEmpty { parts.append(dt) }
    if let due = it.due, ItemSchedule.parseDay(due) != nil { parts.append("~\(due)") }
    if let rs = it.resurface, ItemSchedule.parseDay(rs) != nil { parts.append("↻\(rs)") }
    return parts.joined(separator: " · ")
}

// MARK: - 표준 확인·안내 대화상자 (앱 공용 형식 — confirm-dialog-style)
// 배경 딤 + 가운데 카드 + 큰 제목(표준 alert보다 2단계) + 하단 버튼 행.
// 사용처: 기억하기 재확인 · 원칙 자동결정 안내 · 삭제 확인(상세·리스트 공통).

struct StandardDialog<Buttons: View>: View {
    let title: String
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 0) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20).padding(.vertical, 24)
                Divider().overlay(Palette.border)
                buttons()
            }
            .frame(width: 300)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        }
    }
}

/// 대화상자 하단 버튼. prominent = 굵게(주 액션). tint로 색을 덮어씀(삭제=overdue 등).
struct DialogButton: View {
    let title: String
    var prominent: Bool = false
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(prominent ? .title3.weight(.semibold) : .title3)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .foregroundStyle(tint ?? (prominent ? Palette.accent : Palette.textSecondary))
    }
}

/// 두 버튼(취소/확정) 표준 확인 대화상자 — 가장 흔한 형태.
struct ConfirmDialog: View {
    let title: String
    var cancelTitle: String = "취소"
    var confirmTitle: String
    var confirmTint: Color? = nil
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        StandardDialog(title: title) {
            HStack(spacing: 0) {
                DialogButton(title: cancelTitle, action: onCancel)
                Divider().overlay(Palette.border)
                DialogButton(title: confirmTitle, prominent: true, tint: confirmTint, action: onConfirm)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
