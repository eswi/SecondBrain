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
            // **시각 인지 게이트(2026-08-03, #3).** 그 시점이 **오면(지났으면) 게시**한다.
            // - 시각 있는 미리 알림: 그 시각부터 게시. **지난 시각은 계속 보임**(아침 약을 오후에 열어도 목록에 남음 —
            //   시각 지났다고 빠지면 놓친 것을 숨기게 되어 원칙에 어긋남).
            // - date-only: `parseDay`가 자정을 주므로 `자정 ≤ now` = **오늘 자정부터**(기존 동작 불변).
            return rd <= now
        }
        if ClassSpecCatalog.uses(it.type, .due),
           let d = it.due, let dd = parseDay(d, calendar: calendar) {
            // 되풀이는 마감(회차 앵커)도 **시각 인지** — 미리 알림 없이 마감만 있으면 **마감 시각부터** 게시(#3).
            // 일반 항목은 기존대로: 마감만 있으면 먼 미래여도 게시(마감=기한이라 미리 챙기게).
            return it.type == "recurrence" ? dd <= now : true
        }
        return false
    }

    /// 분류 게이트 통과 + 실제 날짜인 **미리 알림(resurface)만**. 아니면 nil. `deadlineDay`(마감)의 짝.
    /// 캡션·목록이 "이 분류가 쓰는 칸의 날짜"만 노출하도록 — 화면(상세 "시간 설정")과 같은 게이트를 탄다.
    public static func gatedResurface(_ it: ResolvedItem) -> String? {
        if ClassSpecCatalog.uses(it.type, .resurface),
           let r = it.resurface, parseDay(r) != nil { return r }
        return nil
    }

    /// "YYYY-MM-DD" 또는 "YYYY-MM-DD'T'HH:mm"("...  HH:mm"도 관대 수용) → Date. 형식 안 맞으면 nil.
    /// (시각 도입, 2026-08-02 · 방식(a) recurrence-design.md §6-A/§6-B)
    /// - 시각이 없으면 **그 날 자정**(기존 동작 그대로 — 모든 게이트가 `startOfDay`로 감싸므로 날 단위 판정 불변).
    /// - 시각이 있으면 그 시각.
    /// - **시각 부분만 깨진 경우엔 날짜를 살려 자정**으로 판정한다(유실 방지 — 값은 안 지운다).
    ///   여기가 진앙: 옛/새 형식을 **모두** 받게 하는 것이 전체 안전의 열쇠. 실패는 에러가 아니라 "조용한 강등"이라 테스트로 잡는다.
    public static func parseDay(_ s: String, calendar: Calendar = .current) -> Date? {
        let (datePart, timePart) = splitDateTime(s)
        let p = datePart.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        var comps = DateComponents(year: y, month: m, day: d)
        if let hm = timePart.flatMap(parseHM) { comps.hour = hm.hour; comps.minute = hm.minute }
        return calendar.date(from: comps)
    }

    /// 값에 붙은 **유효한 시각(HH:mm)** 만 꺼낸다. 시각이 없거나 깨졌으면 nil. 알림·표시 전용.
    /// (날짜 판정은 `parseDay`가, 하루 안의 시각은 이 함수가 담당 — 역할 분리.)
    public static func timeOfDay(_ s: String) -> (hour: Int, minute: Int)? {
        let (_, timePart) = splitDateTime(s)
        return timePart.flatMap(parseHM)
    }

    /// 날짜부와 (있으면) 시각부로 가른다. 구분자는 `T` 또는 공백(읽기 관대). **쓰기 표준형은 `T`**(§6-B).
    private static func splitDateTime(_ s: String) -> (date: String, time: String?) {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let i = t.firstIndex(where: { $0 == "T" || $0 == " " }) else { return (t, nil) }
        let time = t[t.index(after: i)...].trimmingCharacters(in: .whitespaces)
        return (String(t[..<i]), time)
    }

    /// "HH:mm" → (시,분). 범위 밖(시 0..<24·분 0..<60)이거나 형식이 안 맞으면 nil.
    private static func parseHM(_ s: String) -> (hour: Int, minute: Int)? {
        let p = s.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return (h, m)
    }

    /// Date → "YYYY-MM-DD"(로케일 무관). parseDay의 역.
    public static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Date → **쓰기 표준형** "YYYY-MM-DD'T'HH:mm"(§6-B — 쓰기는 항상 `T`). 시각 포함 저장용.
    public static func dayTimeString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// `s`의 **날짜부**에, `source`에 시각이 있으면 그 시각을 붙여 돌려준다(없으면 날짜만).
    /// 미루기·날짜 변경이 **원래 시각을 보존**하도록 쓴다(§6-B: 약 아침 8시 → 미뤄도 8시).
    public static func withTimeOfDay(_ s: String, from source: String?) -> String {
        let (datePart, _) = splitDateTime(s)
        guard let source, let t = timeOfDay(source) else { return datePart }
        return String(format: "%@T%02d:%02d", datePart, t.hour, t.minute)
    }

    /// **하루 안 보조 표시** — 값에 시각이 있고 그 날짜가 **오늘**일 때만, 남은/지난 시간을 사람이 읽는 문구로.
    /// D-day(날 단위)를 보완한다(§6-B: "오늘/지남만 19:00 · N시간 남음"). 오늘 아니거나 시각 없으면 nil.
    public static func withinDayCaption(_ value: String, now: Date, calendar: Calendar = .current) -> String? {
        guard timeOfDay(value) != nil, let target = parseDay(value, calendar: calendar) else { return nil }
        guard calendar.isDate(target, inSameDayAs: now) else { return nil }   // 오늘만(다른 날은 D±n 배지가 담당)
        let secs = target.timeIntervalSince(now)
        if secs <= 0 { return "지남" }
        let mins = Int(secs / 60)
        if mins < 60 { return mins <= 1 ? "곧" : "\(mins)분 남음" }
        return "\(mins / 60)시간 남음"
    }

    // MARK: 규칙 1 — 미리 알림은 마감보다 최소 하루 빠르게 (2026-07-30)
    // 규칙은 여기 Core 한 곳에 두고 세 곳(날짜 선택·자동 분류·미루기)이 이걸 쓴다. 복사 금지.

    /// **규칙 1 — 미리 알림은 마감보다 실제로 앞서야 한다.** 규칙이 바뀐 게 아니라 **시각 유무로 적용이 갈린다**(2026-08-03):
    /// - **시각 없으면(date-only):** 날짜 단위로만 비교 가능 → **최소 하루 전**(마감−1일). (기존 그대로.)
    /// - **시각 있으면:** 시각으로 비교 → **마감보다 앞서거나 같으면 됨**(`미리 알림 ≤ 마감`, 이후만 위반).
    /// 마감이 **미래**일 때만(지난 마감 미루기는 제약 없음). 목적: 항목이 자기 마감을 지날 때까지 숨는 것을 막는다.
    /// (참고: 미리 알림 = 마감(정각)은 허용하되 실질 lead가 0 — 되풀이는 마감 분기도 시각 인지라 미리 알림 없어도 마감 시각부터 보임.)

    /// 미리 알림 **날짜 상한**(DatePicker 범위·미루기용). 없으면(제약 없음) nil.
    /// `resurfaceHasTime`=true면 마감의 **날까지 허용**(같은 날 — 시각 검증은 `violatesRule1`이); false면 마감−1일.
    public static func resurfaceUpperBound(due: String?, now: Date, resurfaceHasTime: Bool = false,
                                           calendar: Calendar = .current) -> Date? {
        guard let due, let dd = parseDay(due, calendar: calendar) else { return nil }   // 마감 없음
        guard dd > now else { return nil }                                              // 마감 오늘/지남(시각 인지)
        let startDue = calendar.startOfDay(for: dd)
        return resurfaceHasTime ? startDue : calendar.date(byAdding: .day, value: -1, to: startDue)
    }

    /// 규칙 1 위반 여부 — 최종 방어선(시각 인지). 마감 없음/지남·미리 알림 없음이면 false.
    public static func violatesRule1(resurface: String?, due: String?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let due, let dd = parseDay(due, calendar: calendar),
              let resurface, let rd = parseDay(resurface, calendar: calendar) else { return false }
        guard dd > now else { return false }                                            // 마감 미래일 때만
        if timeOfDay(resurface) != nil {
            return rd > dd                                                              // 시각: 마감 이후만 위반(≤ 마감 OK)
        }
        return calendar.startOfDay(for: rd) >= calendar.startOfDay(for: dd)             // date-only: 같은 날부터 위반(하루 전)
    }

    /// 미루기(+7일)의 결과 — 규칙 1을 지키며 결정한다. **위반 상태로 저장하는 경로는 없다.**
    public enum DeferOutcome: Equatable {
        /// 미룸 — `to`(YYYY-MM-DD)로 저장. `capped`=true면 상한(마감−1일)에 걸려 당겨졌다는 뜻(알린다).
        case deferred(to: String, capped: Bool)
        /// 못 미룸 — 마감 하루 전(`cap`, YYYY-MM-DD)이 오늘이거나 지나 미룰 여지가 없다(알린다).
        case blocked(cap: String)
    }

    /// "+7일 미루기"를 규칙 1 안에서 계산한다:
    /// - 마감 없음/지남 → 오늘+7일 그대로(`capped:false`).
    /// - 마감 하루 전이 아직 미래면 → 오늘+7일이 그 상한을 넘으면 상한까지 당겨서(`capped:true`), 안 넘으면 그대로.
    /// - 마감 하루 전이 오늘이거나 지났으면 → `blocked`(미루지 않는다).
    public static func deferSevenDays(due: String?, now: Date, resurfaceHasTime: Bool = false,
                                      calendar: Calendar = .current) -> DeferOutcome {
        let today = calendar.startOfDay(for: now)
        let target = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        guard let ub = resurfaceUpperBound(due: due, now: now, resurfaceHasTime: resurfaceHasTime, calendar: calendar) else {
            return .deferred(to: dayString(target, calendar: calendar), capped: false)   // 마감 없음/지남
        }
        if ub <= today {                                                                 // 마감 하루 전 = 오늘/과거
            return .blocked(cap: dayString(ub, calendar: calendar))
        }
        if target > ub {                                                                 // 상한 넘음 → 당겨서
            return .deferred(to: dayString(ub, calendar: calendar), capped: true)
        }
        return .deferred(to: dayString(target, calendar: calendar), capped: false)       // 상한 안 → 그대로
    }
}
