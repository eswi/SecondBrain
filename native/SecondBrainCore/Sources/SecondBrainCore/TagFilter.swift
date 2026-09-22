import Foundation

/// **해시태그 필터** — 목록 화면의 가장자리 손잡이를 누르면 나오는 것(정본 = `docs/native/tag-filter-design.md` · 2026-09-22 사용자 결정).
///
/// - `selected` = 고른 태그 글(중복 선택) · `includesUntagged` = 「태그 없음」을 골랐다 · `inverted` = 「역선택」이 켜졌다.
/// - **활성이 아니면 전부 통과.** 활성이면 `(선택 ∩ 태그 ≠ ∅) ∨ (태그없음 ∧ 태그 = ∅)`, 역선택이면 그 부정(정확히 여집합 · 시험 3).
/// - 여러 태그를 골랐을 때는 **하나라도 가진** 기억이 걸린다(OR · 설계 §2 4번 — 「태그 없음」과 함께 고를 수 있으려면 OR이어야 한다).
/// - 화면에 나열된 태그(`available`)는 **필터 걸기 전** 목록에서 뽑는다 — 아니면 하나 고르는 순간 다른 칩이 사라져 중복 선택이 안 된다.
/// - `pruned(to:)` — 화면에 없는 태그는 거를 때 세지 않는다(보이지 않는 필터에 갇히지 않게 · 설계 §2 16번).
public struct TagFilter: Equatable, Sendable {
    public var selected: Set<String> = []
    public var includesUntagged: Bool = false
    public var inverted: Bool = false

    public init(selected: Set<String> = [], includesUntagged: Bool = false, inverted: Bool = false) {
        self.selected = selected; self.includesUntagged = includesUntagged; self.inverted = inverted
    }

    /// 무엇이든 골라져 있나. ⚠️ 역선택만 켜진 것은 활성이 아니다 — 고른 것이 없으면 「선택되지 않은 기억」 = 전부다.
    public var isActive: Bool { !selected.isEmpty || includesUntagged }

    /// 이 태그들을 가진 기억이 보이나.
    public func matches(_ tags: [String]) -> Bool {
        guard isActive else { return true }
        let base = tags.contains(where: selected.contains) || (includesUntagged && tags.isEmpty)
        return inverted ? !base : base
    }

    public mutating func toggle(_ tag: String) {
        if selected.contains(tag) { selected.remove(tag) } else { selected.insert(tag) }
    }

    /// 화면에 있는 태그만 남긴 필터 — 「태그 없음」·「역선택」은 그대로.
    public func pruned(to available: [String]) -> TagFilter {
        var f = self
        f.selected = selected.intersection(available)
        return f
    }

    /// 목록의 태그 전부 — 중복 제거 · 글 정렬. 빈 값(지운 태그)은 `HashTag.tags(in:)`이 이미 걸렀다.
    public static func available(in items: [ResolvedItem]) -> [String] {
        var seen = Set<String>()
        for it in items { for t in it.hashtags { seen.insert(t.text) } }
        return seen.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// **제목의 숫자 셋**(2026-09-22 사용자 · 설계 §7) — `total` = 거르는 대상 전부 · `selected` = 고른 것에 **걸린** 기억 · `rest` = 나머지.
    /// ⚠️ **「역선택」과 무관하다** — 역선택은 무엇을 **보이나**를 뒤집을 뿐, 무엇이 **선택됐나**는 그대로다(Claude 판단 · 설계 §7). 고른 것이 없으면 `selected` = 0.
    public func counts(in items: [ResolvedItem]) -> (total: Int, selected: Int, rest: Int) {
        var f = self; f.inverted = false
        let sel = f.isActive ? items.filter { f.matches($0.hashtags.map(\.text)) }.count : 0
        return (items.count, sel, items.count - sel)
    }

    /// 목록을 거른다(순서 유지).
    public func apply(_ items: [ResolvedItem]) -> [ResolvedItem] {
        guard isActive else { return items }
        return items.filter { matches($0.hashtags.map(\.text)) }
    }
}
