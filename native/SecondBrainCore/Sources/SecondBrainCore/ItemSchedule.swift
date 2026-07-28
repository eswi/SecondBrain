import Foundation

/// 항목의 "유효 시점" 계산 — 알림·섹션(곧 닥칠 것)·D-day가 공유하는 단일 진실원.
/// 규칙: resurface(다시 들이밀 날짜) 우선, 없으면 due(마감).
/// **실제 날짜(YYYY-MM-DD)로 파싱되는 것만** 시점으로 본다 — none·빈값·깨진 값,
/// 그리고 레거시 "weekly"(= 날짜 없음의 동의어)까지 전부 균일하게 "시점 없음".
public enum ItemSchedule {
    /// 유효 시점 날짜 문자열("YYYY-MM-DD") 또는 nil(시점 없음).
    public static func effectiveDay(_ it: ResolvedItem) -> String? {
        if let r = it.resurface, parseDay(r) != nil { return r }
        if let d = it.due, parseDay(d) != nil { return d }
        return nil
    }

    /// "YYYY-MM-DD" → 그 날 자정 Date. 형식 안 맞으면 nil.
    public static func parseDay(_ s: String, calendar: Calendar = .current) -> Date? {
        let p = s.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }
}
