import Foundation

/// 항목의 "유효 시점" 계산 — 알림·섹션(곧 닥칠 것)·D-day가 공유하는 단일 진실원.
/// 규칙: resurface(다시 들이밀 날짜) 우선, 없으면 due(마감).
/// **실제 날짜(YYYY-MM-DD)로 파싱되는 것만** 시점으로 본다 — none·빈값·깨진 값,
/// 그리고 레거시 "weekly"(= 날짜 없음의 동의어)까지 전부 균일하게 "시점 없음".
///
/// §7 (c)(Stage D3-B): 여기에 **분류 게이트**가 있다 — 그 분류가 안 쓰는 칸의 날짜는 시점이 아니다.
/// 게이트를 이 한 곳에 두면 소비자(`NotificationPlanner`·`InboxSectionizer`)가 자동으로 상속한다.
public enum ItemSchedule {
    /// 유효 시점 날짜 문자열("YYYY-MM-DD") 또는 nil(시점 없음).
    ///
    /// **칸별로 따로 판단한다** — "시간 안 쓰는 분류면 통째로 nil"이 아니다.
    /// 주차는 다시 보기는 쓰고 마감만 안 쓰므로, resurface 날짜는 살고 due 날짜만 막힌다.
    /// 정의 없는 분류(미분류·discard·미등록)는 `ClassSpecCatalog.uses`가 '전부 씀'으로 폴백 →
    /// 분류가 없어서 날짜가 조용히 사라지는 일은 없다(화면의 "시간 설정"과 같은 함수·같은 폴백).
    public static func effectiveDay(_ it: ResolvedItem) -> String? {
        if ClassSpecCatalog.uses(it.type, .resurface),
           let r = it.resurface, parseDay(r) != nil { return r }
        if ClassSpecCatalog.uses(it.type, .due),
           let d = it.due, parseDay(d) != nil { return d }
        return nil
    }

    /// "YYYY-MM-DD" → 그 날 자정 Date. 형식 안 맞으면 nil.
    public static func parseDay(_ s: String, calendar: Calendar = .current) -> Date? {
        let p = s.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }
}
