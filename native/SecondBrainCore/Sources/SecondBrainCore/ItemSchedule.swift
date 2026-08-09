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
        // **꺼둔 되풀이는 게시 안 함**(2026-08-03) — 상세 배너의 "되살아나기 멈춤" 약속.
        // 사라지는 게 아니라 시점 없는 쪽(`recent`)으로 옮겨간다(위 §7(c) 원칙 그대로, 총 개수 보존).
        // 화면에선 확정 여부로 갈린다 — **확정이면 '살아있는 기억' 탭, 미확정이면 '새 기억들' 섹션**
        // (`InboxModel.partition`이 `recent`를 그 둘로 쪼갠다). 어느 쪽이든 항목은 남는다.
        if Recurrence.isDormant(it) { return false }
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

    /// 규칙 1 위반 여부를 **저장될 최종 쌍**으로 판정한다 — 화면 draft 쌍이 아니라
    /// "**현재 항목 + 이번에 저장할 변경**"을 필드별 LWW로 겹친 결과.
    ///
    /// **왜 이 함수가 따로 필요한가 (2026-08-06 `가`):** 위 `violatesRule1`은 넘겨받은 두 값만 본다.
    /// 그런데 저장은 `EditDiff`가 낸 **바뀐 필드만** 내보내고 그것이 현재 저장값 위에 얹힌다.
    /// 화면이 낡아지는 경로가 하나라도 있으면(완료→취소·외부 동기화·배경 전진) **적법한 쌍을 검사하고
    /// 위반인 쌍을 저장**한다. 검사와 저장이 같은 쌍을 보게 하는 것이 이 함수의 몫이다.
    /// **되풀이 전용이 아니다** — 부분 저장 + 필드별 LWW를 쓰는 모든 항목에 해당한다.
    ///
    /// - Parameter changes: 저장할 변경(`EditDiff.changes` 결과). 값 지움은 `""`/`"none"` — 둘 다
    ///   `parseDay`가 nil을 주므로 "시점 없음"으로 자연히 처리된다(제약 없음).
    /// - Parameter item: **현재 저장 상태**(화면 스냅숏이 아니라 모델의 최신 항목이어야 한다 — 부르는 쪽 책임).
    public static func violatesRule1(applying changes: [String: String], to item: ResolvedItem,
                                     now: Date, calendar: Calendar = .current) -> Bool {
        violatesRule1(resurface: changes["resurface"] ?? item.resurface,
                      due: changes["due"] ?? item.due,
                      now: now, calendar: calendar)
    }

    // MARK: 규칙 1이 막은 이유 — 미결 3번 (2026-08-07)

    /// **규칙 1이 왜 막았나.** 화면이 **값과 할 일**을 말할 수 있게 이유를 갈라 준다.
    ///
    /// **왜 필요한가:** 규칙 1은 2026-08-03에 **시각 인지**로 갈렸는데(시각 있으면 `미리 알림 ≤ 마감`,
    /// 없으면 마감−1일) **화면 문구는 하나로 남았다** — 「미리 알림은 **마감 하루 전**(◯월 ◯일)까지만…」.
    /// 그래서 시각 위반일 때 ⓐ "하루 전"인데 괄호에는 **마감 당일**이 들어가 문장이 자기모순이고,
    /// ⓑ **원인은 시각인데 날짜만 말해** 사람이 무엇을 고칠지 알 수 없다(이미 그 날짜로 맞춰 뒀으므로).
    ///
    /// **★ 진단: 화면이 규칙을 *설명하려* 해서 생긴 거짓이다.** "하루 전"은 규칙 서술이고, 규칙이 갈리자
    /// 한 문장이 두 규칙을 말하게 됐다. → **값과 할 일만 말하면 규칙이 갈려도 문장이 안 틀린다.**
    ///
    /// **cap·deadline은 저장 표준형 문자열**로 준다 — 사람말 변환은 App(`korDateTime`)이 한다(층 분리).
    /// **`violatesRule1`은 안 건드린다** — 회귀선이 여럿이고 자동 분류(`InboxModel`)는 Bool로 충분하다.
    /// 기존 함수를 두고 얹는 방식은 2026-08-06 (a)와 같다.
    ///
    /// **A(지난 마감 상한 N=7)가 나중에 `case tooFarWhilePastDue(cap:)`를 얹는다** — 그때
    /// `rule1Block`의 `guard dd > now` 분기 하나만 늘면 된다(worklog 2026-08-07 §4-C).
    public enum Rule1Block: Equatable, Sendable {
        /// 미리 알림에 **시각이 없다** — 마감 하루 전까지. `cap` = 마감−1일, `deadline` = 마감.
        case dayBeforeDeadline(cap: String, deadline: String)
        /// 미리 알림에 **시각이 있다** — 마감 시각까지(정각 허용). 상한이 곧 마감이라 `deadline` 하나면 된다.
        case atOrBeforeDeadline(deadline: String)
    }

    /// 저장될 최종 쌍이 규칙 1을 어기면 **왜인지**, 안 어기면 nil.
    /// 입력 규약은 `violatesRule1(applying:to:)`와 같다(현재 저장 상태 + 이번 변경).
    ///
    /// **판정은 `violatesRule1` 하나만 본다** — 막을지 말지와 왜 막았는지가 **갈릴 수 없게** 한다.
    /// 이 함수가 하는 일은 **이미 확정된 위반을 사람이 할 일로 번역하는 것**뿐이다.
    ///
    /// **경우는 여섯인데 갈래는 둘이다** — 사람이 할 일이 **미리 알림에 시각이 있나** 하나로만 갈린다:
    /// 시각 없으면 *"날짜를 마감−1일 이하로"*, 있으면 *"미리 알림을 마감 시각 이하로"*.
    /// 같은 날이든 다른 날이든 시각 있는 쪽은 규칙이 하나(`미리 알림 ≤ 마감`)라 **case를 더 쪼개지 않는다.**
    public static func rule1Block(applying changes: [String: String], to item: ResolvedItem,
                                  now: Date, calendar: Calendar = .current) -> Rule1Block? {
        let resurface = changes["resurface"] ?? item.resurface
        let due = changes["due"] ?? item.due
        guard violatesRule1(resurface: resurface, due: due, now: now, calendar: calendar),
              let due else { return nil }
        // 시각이 있으면 상한이 곧 마감이다 — 상한을 따로 계산할 것이 없다(`미리 알림 ≤ 마감`).
        if timeOfDay(resurface ?? "") != nil { return .atOrBeforeDeadline(deadline: due) }
        guard let ub = resurfaceUpperBound(due: due, now: now, resurfaceHasTime: false,
                                           calendar: calendar) else { return nil }
        return .dayBeforeDeadline(cap: dayString(ub, calendar: calendar), deadline: due)
    }

    // MARK: 늦었는데 숨겨진 것 — D (2026-08-07)

    /// **늦었는데 숨겨진 것.** 마감이 지났는데 미리 알림이 아직이라 **화면 어디에도 안 보이는** 상태.
    ///
    /// **왜 필요한가 (2026-08-07, 실데이터 두 건):** 규칙 1은 *"항목이 자기 마감을 지날 때까지 숨는 것"* 을
    /// 막는데, **마감이 과거면 두 겹(상한·저장 검사)이 다 잠든다**(`resurfaceUpperBound`·`violatesRule1`의
    /// `dd > now` 가드). 지난 것을 미루려면 그 느슨함이 필요해서 그렇게 정한 것이라 **규칙이 틀린 게 아니다.**
    /// 그런데 그 결과가 규칙 1이 막으려던 상태 그대로다 — 그리고 **아무 표시가 없어 사람이 모른다.**
    /// 이 판정은 그 "모름"을 없앤다. **저장값은 안 바꾼다** — 숨기는 것 자체는 사람이 시킨 것이다.
    ///
    /// **실데이터 두 건(2026-08-07 14:3x 전수 스캔, live 106개):**
    /// - `E75C2531` 「우리 샌드박스 협력 병원…」 마감 2026-07-31 · 미리 알림 2026-08-14 (당일 미루기 +7일)
    ///   → **15:32에 사용자가 손으로 해소**(마감 2026-08-14 · 미리 알림 2026-08-10). 16:40 재스캔에선 안 걸린다.
    /// - `AF9BAB30` 「가 - 이른 완료 시험」 마감 2026-08-07 13:00 · 미리 알림 2026-08-08 12:00 (뒤집힌 lead)
    ///
    /// **꺼둔 되풀이는 제외한다** — 그건 사람이 명시적으로 멈춘 것이고 **"되풀이 꺼둠" 배너가 이미 말한다.**
    /// 여기서 또 알리면 같은 사실에 신호가 둘이 된다(색 위계가 죽는 것과 같은 종류의 손해).
    /// **`status=done`은 안 거른다** — 시점 판정에 상태를 섞지 않는다(`isPublished`·`doneThisCycle`과 같은 규약).
    /// 보관함 항목은 애초에 목록에 안 그려지므로 부르는 쪽(`liveNonDone`)이 이미 걸러 준다.
    public struct OverdueHidden: Equatable, Sendable {
        /// 마감 이후 지난 **날 수**(날짜 단위 — 오늘 마감이면 0). "얼마나 늦었나".
        /// ⚠️ **0일도 숨은 것은 사실이다** — 오늘 13:00 마감이 지나고 내일 12:00까지 숨는 `가`가 그 경우다.
        public let lateDays: Int
        /// **다시 보일 날** = 미리 알림 값 그대로("YYYY-MM-DD" 또는 "…T HH:mm"). 숨긴 장본인이다.
        public let returnsOn: String?

        public init(lateDays: Int, returnsOn: String?) {
            self.lateDays = lateDays; self.returnsOn = returnsOn
        }
    }

    /// 위 상태면 값을, 아니면 nil.
    ///
    /// **네 관문 — 순서에 뜻이 있다:**
    /// 1. 꺼둔 되풀이는 먼저 뺀다(배너가 이미 말한다 — 위 참조).
    /// 2. **마감을 쓰는 분류 + 유효한 마감**이어야 "늦음"이 정의된다. 게이트는 화면과 같이 탄다(`ClassSpecCatalog`).
    /// 3. `마감 ≤ now` — **시각 인지**다. 오늘 13:00 마감은 13:00부터 늦은 것이지 자정부터가 아니다.
    /// 4. **`!isPublished` — 숨었나.** 늦었어도 목록에 있으면 알릴 것이 없다.
    ///    ★ 이 절이 *"숨기는 것은 미리 알림이지 마감이 아니다"* 를 담는다 — 미리 알림 없이 마감만 지난
    ///    항목은 게시되므로(2절) 여기서 걸러진다. `isPublished` 하나만 보므로 게이트와 **절대 안 갈린다.**
    public static func overdueHidden(_ it: ResolvedItem, now: Date,
                                     calendar: Calendar = .current) -> OverdueHidden? {
        if Recurrence.isDormant(it) { return nil }                                   // 1
        guard ClassSpecCatalog.uses(it.type, .due),                                  // 2
              let ds = it.due, let dd = parseDay(ds, calendar: calendar) else { return nil }
        guard dd <= now else { return nil }                                          // 3
        guard !isPublished(it, now: now, calendar: calendar) else { return nil }     // 4
        // "얼마나 늦었나"는 **날짜 단위** — 놓침(`Recurrence.missedCount`)과 같은 규약이라 두 숫자가 안 어긋난다.
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: dd),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return OverdueHidden(lateDays: max(0, days), returnsOn: gatedResurface(it))
    }

    /// 미루기(+7일)의 결과 — 규칙 1을 지키며 결정한다. **위반 상태로 저장하는 경로는 없다.**
    public enum DeferOutcome: Equatable {
        /// 미룸 — `to`(YYYY-MM-DD)로 저장. `capped`=true면 상한(마감−1일)에 걸려 당겨졌다는 뜻(알린다).
        case deferred(to: String, capped: Bool)
        /// 못 미룸 — 마감 하루 전(`cap`, YYYY-MM-DD)이 오늘이거나 지나 미룰 여지가 없다(알린다).
        case blocked(cap: String)
    }

    /// **"N일 미루기"를 규칙 1 안에서 계산한다.** 1·3·7일이 **완전히 같은 길**을 탄다(2026-08-09) —
    /// 갈리는 것은 **더하는 날 수 하나뿐**이고, 상한·차단·알림 판정은 전부 공유한다.
    /// 버튼이 셋이 되어도 규칙이 셋으로 갈라지지 않게 하려고 여기 한 함수에 둔다.
    ///
    /// **기준은 언제나 「오늘」이다** — 지금 값 + N일이 아니라 **오늘 + N일**이다(옛 +7일과 같은 규약).
    /// 미루기는 *"오늘부터 N일 뒤에 다시 보여줘"* 라는 뜻이지 *"지금 잡힌 날짜를 더 밀어라"* 가 아니다.
    ///
    /// - 마감 없음/지남 → 오늘+N일 그대로(`capped:false`).
    /// - 마감 상한이 아직 미래면 → 오늘+N일이 그 상한을 넘으면 상한까지 당겨서(`capped:true`), 안 넘으면 그대로.
    /// - 상한이 오늘이거나 지났으면 → `blocked`(미루지 않는다).
    public static func deferBy(days n: Int, due: String?, now: Date, resurfaceHasTime: Bool = false,
                               calendar: Calendar = .current) -> DeferOutcome {
        let today = calendar.startOfDay(for: now)
        let target = calendar.date(byAdding: .day, value: n, to: today) ?? today
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

    /// "+7일 미루기" — `deferBy(days: 7,…)`의 이름 있는 짝. 목록 스와이프 액션이 이 뜻으로 쓴다.
    public static func deferSevenDays(due: String?, now: Date, resurfaceHasTime: Bool = false,
                                      calendar: Calendar = .current) -> DeferOutcome {
        deferBy(days: 7, due: due, now: now, resurfaceHasTime: resurfaceHasTime, calendar: calendar)
    }
}
