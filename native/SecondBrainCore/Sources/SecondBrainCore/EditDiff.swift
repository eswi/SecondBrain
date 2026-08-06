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
    /// draft의 (type/due/resurface/raw)를 원본 항목과 비교해 바뀐 필드만 담은 dict 반환.
    /// 비어 있으면 커밋할 것이 없다(이벤트를 만들지 않는다).
    ///
    /// `raw`(본문): **글자 그대로** 비교한다 — trim·정규화 없음(앞뒤 공백도 사람이 쓴 그대로 보존,
    /// edit-policy.md §6 텍스트 층 가변). `nil`이면 이 diff에 본문을 포함하지 않는다(하위호환 기본값).
    /// "본문 전부 지움" 차단은 UI 정책이므로 여기서 판단하지 않는다(빈값 변경도 diff엔 그대로 담김).
    public static func changes(type: String?, due: String?, resurface: String?,
                               raw: String? = nil, from item: ResolvedItem) -> [String: String] {
        var changes: [String: String] = [:]
        if normType(type) != normType(item.type) {
            changes["type"] = type ?? ""          // 미분류 = "" (기존 set type= 경로와 동일)
        }
        if let v = timeChange(new: due, old: item.due) { changes["due"] = v }
        if let v = timeChange(new: resurface, old: item.resurface) { changes["resurface"] = v }
        if let raw = raw, raw != (item.raw ?? "") { changes["raw"] = raw }   // 글자 그대로(공백 보존)
        return changes
    }

    /// **완료·취소가 저장값을 옮겼을 때 화면 draft에 되받을 칸**을 고른다 (2026-08-06 `가`).
    ///
    /// 완료·취소는 마감·미리 알림을 바꾸는데 화면 draft가 안 따라가면, 그 낡은 값 위에서 부분 저장이
    /// 일어나 **검사한 쌍 ≠ 저장되는 쌍**이 된다(`ItemSchedule.violatesRule1(applying:to:)`가 막는 그 상황).
    /// draft를 같이 옮겨 **낡음 자체를 없애는 것**이 이 함수의 몫이다.
    ///
    /// **⚠️ 사람이 손댄 칸은 절대 건드리지 않는다** — 미저장 편집을 완료가 조용히 지우면 그건 새로운 사고다.
    /// `touched` = 지금 draft가 저장값과 다른 칸(= `changes`의 키). 그 칸은 사람의 값이 이긴다.
    ///
    /// - Parameter applied: 완료·취소가 실제로 쓴 변경(`Recurrence.completionChanges` / 취소의 되돌림).
    /// - Parameter touched: 사람이 이미 고쳐 둔 칸의 이름.
    /// - Returns: draft에 그대로 넣을 `[칸: 값]`. 값이 `""`·`"none"`이면 "시점 없음"(비움)이다.
    ///   여기 **없는 칸은 건드리지 않는다** — "안 바뀜"과 "비움"이 섞이지 않게 키의 유무로 가른다.
    public static func draftSync(applied: [String: String], touched: Set<String>,
                                 fields: Set<String> = ["due", "resurface"]) -> [String: String] {
        applied.filter { fields.contains($0.key) && !touched.contains($0.key) }
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
