import Foundation

/// 상세 화면 draft 편집 → **커밋할 변경 필드만** 산출 (edit-policy.md §2).
///
/// 핵심 불변식: **`confirmed`는 절대 포함하지 않는다** — 수정 ≠ 확정.
/// 확정은 이 경로가 아니라 별도 `Event.confirm`으로만 일어난다(§3 단방향).
///
/// 잡음 이벤트 방지: due/resurface에서 `{nil, "", "none"}`은 모두 "시점 없음"으로
/// 동일 취급한다. 그래서 원래 없던 시점을 손대지 않았는데 `none`이 써지는 일이 없다.
/// 사람이 실제 날짜를 지우면(값 → 비움) 그때만 `"none"`을 **명시적으로** 기록한다.
public enum EditDiff {
    /// draft의 (type/due/resurface)를 원본 항목과 비교해 바뀐 필드만 담은 dict 반환.
    /// 비어 있으면 커밋할 것이 없다(이벤트를 만들지 않는다).
    public static func changes(type: String?, due: String?, resurface: String?,
                               from item: ResolvedItem) -> [String: String] {
        var changes: [String: String] = [:]
        if normType(type) != normType(item.type) {
            changes["type"] = type ?? ""          // 미분류 = "" (기존 set type= 경로와 동일)
        }
        if let v = timeChange(new: due, old: item.due) { changes["due"] = v }
        if let v = timeChange(new: resurface, old: item.resurface) { changes["resurface"] = v }
        return changes
    }

    /// type 정규화: nil·"" = 미분류(동일).
    private static func normType(_ t: String?) -> String { (t?.isEmpty ?? true) ? "" : t! }

    /// 시점 필드 변경 판정. nil = 변경 없음. 값 = 커밋할 문자열.
    /// 비우기(실제 값 → 시점 없음)는 `"none"`으로 명시.
    private static func timeChange(new: String?, old: String?) -> String? {
        let n = normTime(new), o = normTime(old)
        if n == o { return nil }
        return n.isEmpty ? "none" : n
    }

    /// `{nil, "", "none"}` → "" (시점 없음). 실제 값(날짜 등)은 그대로 둔다.
    private static func normTime(_ s: String?) -> String {
        guard let s = s, !s.isEmpty, s != "none" else { return "" }
        return s
    }
}
