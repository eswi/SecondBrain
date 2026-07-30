import Foundation

/// 항목의 시점 계산 — **두 날짜 칸의 역할을 분리한다.**
/// - **미리 알림(resurface)** = 언제부터 '지금 챙길 것'에 보여줄지(게시 시작).
/// - **마감(due)** = 실제 기한. 남은 날짜(D±N) 계산의 유일한 기준.
///
/// 그래서 함수도 둘이다 — 하나가 세 질문(언제 게시·언제 알림·며칠 남음)에 다 답하지 않는다:
/// - `publishDay(_:)` — **게시 시작일**. 미리 알림 우선, 없으면 마감. 알림(NotificationPlanner)과
///   정렬 폴백이 쓴다.
/// - `deadlineDay(_:)` — **마감일**. due만 본다(미리 알림 무시). D-day 배지·카드 색조가 쓴다.
///
/// §7 (c)(Stage D3-B): 두 함수 모두에 **분류 게이트**가 있다 — 그 분류가 안 쓰는 칸의 날짜는 시점이 아니다.
/// 게이트를 여기 한 곳에 두면 소비자(`NotificationPlanner`·`InboxSectionizer`)가 자동으로 상속한다.
public enum ItemSchedule {
    /// **게시 시작일**("YYYY-MM-DD") 또는 nil. 미리 알림(resurface) 우선, 없으면 마감(due).
    ///
    /// **칸별로 따로 판단한다** — "시간 안 쓰는 분류면 통째로 nil"이 아니다.
    /// 주차는 다시 보기는 쓰고 마감만 안 쓰므로, resurface 날짜는 살고 due 날짜만 막힌다.
    /// 정의 없는 분류(미분류·discard·미등록)는 `ClassSpecCatalog.uses`가 '전부 씀'으로 폴백 →
    /// 분류가 없어서 날짜가 조용히 사라지는 일은 없다(화면의 "시간 설정"과 같은 함수·같은 폴백).
    public static func publishDay(_ it: ResolvedItem) -> String? {
        if ClassSpecCatalog.uses(it.type, .resurface),
           let r = it.resurface, parseDay(r) != nil { return r }
        if ClassSpecCatalog.uses(it.type, .due),
           let d = it.due, parseDay(d) != nil { return d }
        return nil
    }

    /// **마감일**("YYYY-MM-DD") 또는 nil. **due만** 본다 — 미리 알림은 마감이 아니다.
    /// D-day 배지와 카드 색조의 유일한 기준. 마감이 없으면(미리 알림만 있어도) 배지를 띄우지 않는다.
    /// 게이트는 그대로 — 그 분류가 마감을 안 쓰면(주차·정보·아이디어·원칙) nil.
    public static func deadlineDay(_ it: ResolvedItem) -> String? {
        if ClassSpecCatalog.uses(it.type, .due),
           let d = it.due, parseDay(d) != nil { return d }
        return nil
    }

    /// **게시 게이트** — 이 항목을 지금 '지금 챙길 것'에 게시할지(Stage 2). 미리 알림 = 게시 시작 게이트.
    /// 순서대로 판정한다:
    /// 1. 분류가 미리 알림을 쓰고 유효 날짜가 있으면 → 그 날짜가 **오늘이거나 지났을 때만** 게시.
    ///    미래면 게시 안 함(미리 알림 = 옵트인 지연 장치 — 도래 전에는 묻어 둔다).
    /// 2. 아니고 분류가 마감을 쓰고 유효 날짜가 있으면 → 게시(**먼 미래여도** — 마감만 있는 항목의
    ///    현재 동작을 바꾸지 않는다. 미리 알림을 안 걸었으면 지연도 없다).
    /// 3. 그 외 → 게시 안 함.
    ///
    /// **게시 안 된 항목은 사라지지 않는다** — 시점 없는 쪽 목록으로 옮겨가고 총 개수는 보존된다(§7(c)).
    public static func isPublished(_ it: ResolvedItem, now: Date, calendar: Calendar = .current) -> Bool {
        if ClassSpecCatalog.uses(it.type, .resurface),
           let r = it.resurface, let rd = parseDay(r, calendar: calendar) {
            return calendar.startOfDay(for: rd) <= calendar.startOfDay(for: now)   // 오늘/과거만 게시
        }
        if ClassSpecCatalog.uses(it.type, .due),
           let d = it.due, parseDay(d, calendar: calendar) != nil {
            return true   // 마감만 — 먼 미래여도 게시(현재 동작 보존)
        }
        return false
    }

    /// "YYYY-MM-DD" → 그 날 자정 Date. 형식 안 맞으면 nil.
    public static func parseDay(_ s: String, calendar: Calendar = .current) -> Date? {
        let p = s.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }
}
