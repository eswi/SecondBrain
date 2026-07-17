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
            ForEach(TypeCatalog.assignable) { m in
                Button {
                    if let k = m.key { onChange(k) }
                } label: {
                    Label(m.label, systemImage: m.symbol)
                }
                .disabled(m.key == item.type)
            }
        } label: {
            let m = TypeCatalog.meta(item.type)
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
        let m = TypeCatalog.meta(type)
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
    if let due = it.due, due != "none", !due.isEmpty { parts.append("~\(due)") }
    if let rs = it.resurface, rs != "weekly", rs != "none", !rs.isEmpty { parts.append("↻\(rs)") }
    return parts.joined(separator: " · ")
}
