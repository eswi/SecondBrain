import Foundation

/// 되풀이(반복) 분류의 세부 설정. **기존 칸(due/resurface/status) 재사용이 아닌 새 필드**로 저장한다.
/// (recurrence-design.md §3 — `MergeEngine`의 필드별 LWW가 새 필드를 코드 추가 없이 자동 병합.)
/// Stage 2 = 설정 저장·표시만. **회차 계산·완료(lastDone)·놓침은 Stage 3·4.**
public enum Recurrence {
    /// 반복 주기. (하루 N회는 후속 — 다중 시각 입력 + 알림 다중 트리거와 함께.)
    public enum Unit: String, CaseIterable, Sendable {
        case daily    // 매일
        case weekly   // 매주 (요일 = 기준 날짜)
        case yearly   // 매년 (월·일 = 기준 날짜)
        public var korean: String {
            switch self {
            case .daily: return "매일"
            case .weekly: return "매주"
            case .yearly: return "매년"
            }
        }
    }

    /// 자동 완성 — 완료를 안 해도 이번 회차가 닫히는 방식(§4). `none`이면 완료만이 닫는 길이라 쌓인다(약).
    public enum AutoComplete: String, CaseIterable, Sendable {
        case none      // 없음
        case noon      // 당일 정오
        case endOfDay  // 당일 지나면
        public var korean: String {
            switch self {
            case .none: return "없음"
            case .noon: return "당일 정오"
            case .endOfDay: return "당일 지나면"
            }
        }
    }

    // 저장 필드 key (새 필드 — Detail 슬롯 아님).
    public static let unitKey = "recur"
    public static let autoKey = "recurAuto"
    public static let pausedKey = "recurPaused"
    public static let pausedAtKey = "recurPausedAt"   // 꺼둔 시점(시각 표준형 T) — 놓침을 안 세는 구간의 시작
    public static let lastDoneKey = "lastDone"   // 마지막 완료 시점(시각 표준형 T)
    /// **회차 전진이 미리 알림을 당겼을 때 맞춘 값**((c), 2026-08-08). 배너가 이 값을 그대로 말한다.
    /// **한 회차만 산다** — 다음 전진이 빈 값으로 덮는다(지우는 조건 ㄱ). 왜 그렇게 정했는지는
    /// `clampToRule1` 주석 참조. 값이 있다는 것 = "직전 전진에서 앱이 네 값을 옮겼다".
    public static let leadClampedKey = "recurLeadClamped"

    /// **완료가 회차를 옮긴 목적지**(= 그 완료가 만든 `due` 값) — "지금의 `due`는 완료로 열린 것인가"의 증인.
    /// (2026-08-05, (b) "닫은 회차를 기록" 결정. 정본 §5-B.)
    ///
    /// **필드가 답을 못 해서 표시를 못 고쳤다.** `completionAdvance`와 `catchUpChanges`가 **같은 `advanceBy`** 로
    /// 마감을 옮기고 catch-up은 `lastDone`을 안 건드리므로, 데이터엔 "언제 완료했나"만 있고
    /// **"어느 회차를 닫았나"가 없었다** → 이른 완료(A)와 넘어감(B)의 필드 모양이 같았다(§5-B 계측 표).
    /// 이 필드가 그 답이다.
    ///
    /// **"닫은 회차"가 아니라 "전진한 목적지"를 적는다** (§5-B 스케치와 다른 점 — 의도적):
    /// 밀린 완료(마감 08-02를 08-05에 완료 → k=4회차 전진)에서 "닫은 회차"를 적으면 현재 `due`와의 거리 k가
    /// 데이터에 없어 판정이 다시 휴리스틱이 된다. 그리고 그 경우가 하필 **"3일 놓친 약을 오늘 먹기"**,
    /// 이 설계의 출발점이다. 목적지를 적으면 **`lastDoneDue == due` 등식 하나**로 끝나고 k와 무관하다.
    /// 병합에서도 안전하다 — 두 기기의 완료·catch-up이 필드별 LWW로 엇갈리면 등식이 깨져
    /// **under-claim(안전) 쪽으로 강등**되지, 거짓 완료가 되지 않는다. 닫은 회차 자체는 이벤트 로그에 남는다.
    ///
    /// **값 형식 = `due`의 형식을 그대로 복사**(T 표준형을 강제하지 않는다). due에 시각이 있으면 `...T08:00`,
    /// date-only 되풀이면 `2026-08-06`. `formatLike` 원칙과 같다 — 없는 시각을 만들어 붙이지 않는다.
    /// 비교는 `parseDay`로 파싱해서 하므로 형식이 갈려도 거짓 양성이 안 난다.
    ///
    /// **catch-up·켜기 보정은 이 필드를 절대 안 건드린다** — 그게 "완료"와 "넘어감"을 가르는 정보다.
    /// 문장이 아니라 구조로 지킨다: `advanceBy`는 due/resurface만 쓰고, 이 필드는 `completionChanges`만 얹는다
    /// (회귀선 = `RecurrenceHolesTests.testNet_catchUpAndResumeNeverWriteCompletionFields`).
    public static let lastDoneDueKey = "lastDoneDue"

    /// 마지막 완료 시점(없거나 못 읽으면 nil). 형식 = 시각 표준형 "YYYY-MM-DD'T'HH:mm".
    public static func lastDone(_ it: ResolvedItem, calendar: Calendar = .current) -> Date? {
        it.fields[lastDoneKey].flatMap { ItemSchedule.parseDay($0, calendar: calendar) }
    }

    /// 완료가 옮긴 목적지(없거나 못 읽으면 nil). 이 값이 있으면 새 판정, 없으면 옛 항목 폴백.
    public static func lastDoneDue(_ it: ResolvedItem, calendar: Calendar = .current) -> Date? {
        it.fields[lastDoneDueKey].flatMap { ItemSchedule.parseDay($0, calendar: calendar) }
    }

    /// **이번 회차를 실제로 완료했나** — 표시(칩·배너)·완료 버튼·취소 버튼·재완료 가드가 **모두 이 하나**를 본다.
    /// (2026-08-05 (b) Stage 2. 정본 §5·§5-A·§5-B.)
    ///
    /// **세 절, 각각 하는 일:**
    /// 1. `마감 > now` — 앵커가 미래여야 이번 회차가 닫힌 것. 꺼둔 항목이 앵커를 지나도 칩이 안 남게 하는 절이기도 하다
    ///    (꺼둠은 영영 게시가 안 되므로 3절만으론 칩이 영구히 남는다).
    /// 2. `lastDoneDue == 마감` — **완료 vs 넘어감.** 마감 전진은 자동완성(catch-up)으로도 일어나는데 그건
    ///    "했다"가 아니라 "넘어갔다". catch-up은 이 필드를 안 쓰므로 등식이 깨진다 → **판정으로** 갈린다
    ///    (문장이 아니라 구조. `RecurrenceHolesTests.testNet_catchUpAndResume...`).
    /// 3. `!isPublished` — **다음 회차가 아직 안 열렸다.** 이 절이 구멍 2(lead 창의 거짓 완료)를 닫는다.
    ///
    /// **왜 3절이 필요한가 (2026-08-05 계측):** §5-B는 *"`마감 > now`가 게이트가 숨기는 조건과 같은 사실이라
    /// 둘이 갈릴 수 없다"* 고 적었는데 **lead가 있으면 틀리다** — 게이트는 `resurface`를, 판정은 `due`를 본다.
    /// lead 창(미리 알림~마감)에선 항목이 '지금 챙길 것'에 있는데 칩이 "완료"였다(= 안 먹은 약을 먹었다고 함).
    /// under-claim은 사람이 다시 누르면 되지만 **거짓 완료는 약을 안 먹고 넘어가게 만든다.**
    /// 이제 "회차가 열렸나"는 게이트 하나가 정하고, 판정은 그것을 그대로 쓴다.
    ///
    /// **옛 항목 폴백:** `lastDoneDue`가 없으면(이 변경 전에 만들어진 항목) **옛 판정 그대로**.
    /// 마이그레이션 안 한다(저장소 원칙) — 항목은 다음 완료 때 필드를 얻어 저절로 새 경로로 옮겨간다.
    /// 폴백은 이른 완료를 under-claim한다(그게 옛 동작이다). 회귀선 =
    /// `RecurrenceHolesTests.testNet_oldItemsWithoutNewFieldKeepTodaysVerdict`.
    ///
    /// 앵커(마감)·주기 없으면 "이번 회차" 자체가 정의 안 되므로 false(되풀이는 마감=앵커가 전제, §3-A).
    public static func doneThisCycle(_ it: ResolvedItem, now: Date, calendar: Calendar = .current) -> Bool {
        guard it.type == "recurrence", let u = unit(it),
              let dueStr = it.due, let due = ItemSchedule.parseDay(dueStr, calendar: calendar) else { return false }
        guard due > now else { return false }                                   // 1. 마감 미래여야 이번 회차 닫힘
        if let dest = lastDoneDue(it, calendar: calendar) {                      // ── 새 판정
            return dest == due                                                   // 2. 완료가 만든 마감인가
                && !ItemSchedule.isPublished(it, now: now, calendar: calendar)   // 3. 다음 회차가 아직 안 열렸나
        }
        guard let ld = lastDone(it, calendar: calendar) else { return false }    // ── 옛 항목 폴백(무변경)
        return ld >= stepBack(due, by: u, calendar: calendar)
    }

    /// **완료 버튼이 낼 이벤트 필드 — 분류로 분기(§5, Stage 3의 핵심).**
    /// - 되풀이 → **마지막 완료 시점만 기록**(status 안 건드림 → 항목이 살아있음, 안 사라짐).
    /// - 그 외 → **status=done**(영구 종료·보관함행 — 기존 동작 그대로).
    /// - **재완료는 멱등**(D-3 (a), 2026-08-05) — 이미 닫은 회차에 또 누르면 **빈 변경**을 돌려준다.
    /// - **완료만이 `lastDoneDue`를 쓴다**(2026-08-05) — 전진한 목적지를 함께 적어 catch-up의 전진과 갈라놓는다.
    ///   앵커가 없어 전진할 게 없으면 안 적는다(등식이 성립할 `due`가 없으므로).
    public static func completionChanges(for it: ResolvedItem, now: Date, calendar: Calendar = .current) -> [String: String] {
        guard it.type == "recurrence" else { return ["status": "done"] }
        if doneThisCycle(it, now: now, calendar: calendar) { return [:] }   // 재완료 멱등 — 표시와 **같은 판정**
        var c = [lastDoneKey: ItemSchedule.dayTimeString(now, calendar: calendar)]
        if let adv = completionAdvance(it, now: now, calendar: calendar) {
            c.merge(adv) { _, new in new }   // 마감(회차)·미리 알림을 다음 회차로 → 게시 게이트가 즉시 숨긴다(#1·#2)
            if let newDue = adv["due"] { c[lastDoneDueKey] = newDue }   // 목적지 = 완료의 증인
        }
        return c
    }

    // **`alreadyClosedThisCycle`는 삭제됐다** (2026-08-05, (b) Stage 2).
    //
    // D-3 (a)에서 "새 필드 없이" 재완료를 막으려고 `stepBack(due)`를 방금 닫은 회차로 삼는 휴리스틱 2절을
    // 뒀었는데, 그 2절의 `now ≤ 직전 회차` 조건이 **회차 시각을 지나면 풀렸다**(구멍 1, 계측 2026-08-05):
    // 이른 완료 07:30 → 08:01·09:00·23:00의 재압이 전부 통과해 마감을 08-07로 또 밀었다.
    // 즉 (a)가 막은 것은 회차 시각 **이전**의 재압뿐이었고 데이터 유실 경로는 열려 있었다.
    // §5-B가 후보 ①(가드형)의 단점으로 지적한 "시간이 지나면 다시 벌어진다"가 이 가드 자체에 있었던 셈.
    //
    // 이제 **가드 = 표시 = `doneThisCycle`** 하나다. 그래서:
    // - **dead button이 구조적으로 사라진다** — 판정이 false여서 버튼이 보이는 상태에서 누르면
    //   `completionAdvance`가 반드시 마감을 미래로 밀고 `lastDoneDue`를 같이 써서 판정이 참이 된다.
    //   `DetailView`의 낙관적 `cycleDoneLocal = true`가 재계산과 **항상 일치**한다.
    // - 옛 항목(필드 없음)도 안전하다 — 첫 압이 필드를 심으므로 두 번째 압부터는 새 판정이 본다.
    // - 하루 N회를 넣을 때 재검토할 휴리스틱이 남아 있지 않다(등식은 시각별 회차에도 그대로 성립).

    /// **완료 취소용 — 어떤 필드든 직전 값**(이벤트 이력의 두 번째 최신). 없으면 nil.
    /// 완료는 lastDone·resurface 둘 다 바꾸므로 되돌리기도 둘 다 이걸로 복원한다(streak·회차 보존).
    public static func priorValue(in events: [Event], id: String, key: String) -> String? {
        let vals = events
            .filter { $0.id == id && $0.fields[key] != nil }
            .sorted { $0.hlc < $1.hlc }
            .map { $0.fields[key]! }
        guard vals.count >= 2 else { return nil }
        let prior = vals[vals.count - 2]
        return prior.isEmpty ? nil : prior
    }
    public static func priorLastDone(in events: [Event], id: String) -> String? {
        priorValue(in: events, id: id, key: lastDoneKey)
    }

    // MARK: 회차 계산 (Stage 4) — **앵커 = 마감(due) = 회차 시각.** 미리 알림(resurface) = 게시 시작(lead).
    // 완료·catch-up은 마감을 전진시키고 미리 알림도 **같은 횟수만큼** 전진(lead 보존). 순수 함수.

    /// 주기만큼 뒤의 회차. (하루 N회는 후속.)
    public static func step(_ date: Date, by unit: Unit, calendar: Calendar = .current) -> Date {
        switch unit {
        case .daily:  return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .yearly: return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }

    /// 주기만큼 **앞의** 회차(`step`의 역). `doneThisCycle`이 "직전(방금 닫힌) 회차 시각"을 구할 때만 쓴다.
    public static func stepBack(_ date: Date, by unit: Unit, calendar: Calendar = .current) -> Date {
        switch unit {
        case .daily:  return calendar.date(byAdding: .day, value: -1, to: date) ?? date
        case .weekly: return calendar.date(byAdding: .day, value: -7, to: date) ?? date
        case .yearly: return calendar.date(byAdding: .year, value: -1, to: date) ?? date
        }
    }

    /// `base`에서 시작해 **`pivot`보다 큰(엄격히 미래) 첫 회차.** 완료·전진의 유일한 계산.
    public static func firstOccurrence(after pivot: Date, from base: Date, unit: Unit, calendar: Calendar = .current) -> Date {
        var o = base, n = 0
        while o <= pivot, n < 100_000 { o = step(o, by: unit, calendar: calendar); n += 1 }
        return o
    }

    /// **놓친 회차 수** — 현재 회차(base)부터 **오늘 자정 전까지** 지난 회차 수(오늘 것은 놓침 아님). base 미래면 0.
    public static func missedCount(base: Date, unit: Unit, now: Date, calendar: Calendar = .current) -> Int {
        let startToday = calendar.startOfDay(for: now)
        var o = base, n = 0, guardN = 0
        while calendar.startOfDay(for: o) < startToday, guardN < 100_000 { n += 1; o = step(o, by: unit, calendar: calendar); guardN += 1 }
        return n
    }

    /// 저장 형식 — 원본에 시각이 있었으면 시각 포함, 아니면 날짜만.
    private static func formatLike(_ date: Date, source: String, calendar: Calendar) -> String {
        ItemSchedule.timeOfDay(source) != nil ? ItemSchedule.dayTimeString(date, calendar: calendar)
                                              : ItemSchedule.dayString(date, calendar: calendar)
    }

    /// 마감(앵커)을 **k회** 전진시킨 값 + 미리 알림도 **같은 k회** 전진(lead 보존)한 값을 changes로.
    ///
    /// **(c) 2026-08-08 — lead가 뒤집혀 있으면 여기서 끊는다.** 옛 코드는 lead를 **묻지 않고** 옮겼다.
    /// 뒤집힌 lead(미리 알림이 마감보다 늦음)는 마감이 **과거**일 때 정당하게 생긴다(규칙 1이 자는 구간 —
    /// 지난 것을 미루려면 필요한 느슨함). 문제는 전진이 **그 쌍을 미래로 옮긴다**는 것이다.
    /// 미래에선 규칙 1이 깨어 있는데 이 경로는 [저장] 검사를 안 탄다(`markDone`이 이벤트를 바로 쓴다)
    /// → 위반이 검사 없이 들어가고 **회차마다 자기를 복제한다.**
    ///
    /// **세 경로(완료·자동 완성·켜기)가 다 이 함수를 쓴다** — 그래서 clamp도 여기 한 곳이다. 복사 금지.
    private static func advanceBy(_ it: ResolvedItem, steps k: Int, dueDate: Date, dueStr: String,
                                  unit u: Unit, now: Date, calendar: Calendar) -> [String: String] {
        var changes: [String: String] = [:]
        var od = dueDate; for _ in 0..<k { od = step(od, by: u, calendar: calendar) }
        let newDue = formatLike(od, source: dueStr, calendar: calendar)
        changes["due"] = newDue
        guard let rStr = it.resurface, let rDate = ItemSchedule.parseDay(rStr, calendar: calendar) else { return changes }
        var or = rDate; for _ in 0..<k { or = step(or, by: u, calendar: calendar) }
        let moved = formatLike(or, source: rStr, calendar: calendar)
        let clamped = clampToRule1(moved, due: newDue, now: now, calendar: calendar)
        changes["resurface"] = clamped ?? moved
        // **기록은 바뀔 때만 쓴다.** 안 당겼는데 매 전진마다 빈 값을 쓰면 이벤트 로그가 지저분해진다.
        // 바뀔 때만 쓰면 ⓐ 당김 = 값이 들어가고 ⓑ 다음 전진 = 빈 값으로 덮여 지워진다(지우는 조건 ㄱ).
        let prior = it.fields[leadClampedKey] ?? ""
        let record = clamped ?? ""
        if record != prior { changes[leadClampedKey] = record }
        return changes
    }

    /// **미리 알림이 마감보다 늦으면 규칙 1 안으로 당긴 값**, 안 늦으면 nil(= 안 건드림).
    ///
    /// **판정은 `ItemSchedule.violatesRule1` 하나만 본다** — 당길지와 화면이 막을지가 **갈릴 수 없게**.
    /// (`rule1Block`이 "왜 막았나"를 판정과 갈라놓지 않은 것과 같은 규약.)
    ///
    /// **두 단계로 당긴다 — 사람이 정한 시각을 최대한 지키려고:**
    /// 1. **날짜만** 상한으로 당기고 **시각은 보존**한다(§6-B — "약 아침 8시"는 미뤄도 8시).
    ///    상한은 화면·미루기와 **같은 함수**(`resurfaceUpperBound`)라 셋이 갈릴 수 없다.
    /// 2. 그래도 마감보다 늦으면(같은 날 더 늦은 시각) **마감 시각까지.** 미리 알림 = 마감은 규칙 1이 허용한다.
    ///
    /// **마감이 과거로 떨어지면 당기지 않는다** — `resurfaceUpperBound`가 nil을 준다.
    /// 규칙 1이 자고 있는 구간을 앱이 임의로 깨우면 **그거야말로 조용한 변경**이다.
    static func clampToRule1(_ resurface: String, due: String, now: Date,
                             calendar: Calendar = .current) -> String? {
        guard ItemSchedule.violatesRule1(resurface: resurface, due: due, now: now, calendar: calendar),
              let ub = ItemSchedule.resurfaceUpperBound(due: due, now: now,
                                                        resurfaceHasTime: ItemSchedule.timeOfDay(resurface) != nil,
                                                        calendar: calendar) else { return nil }
        var candidate = ItemSchedule.withTimeOfDay(ItemSchedule.dayString(ub, calendar: calendar), from: resurface)
        if let cd = ItemSchedule.parseDay(candidate, calendar: calendar),
           let dd = ItemSchedule.parseDay(due, calendar: calendar), cd > dd { candidate = due }
        return candidate
    }

    /// **완료 시 회차 전진** — 마감을 `max(now, 현재 마감)` 이후 첫 회차로, 미리 알림도 같은 간격 전진(lead 보존).
    /// 온타임·이른·밀린 경우 다 다음 미래 회차로 넘어가 게이트가 즉시 숨긴다(#1·#2). 앵커(마감) 없으면 nil.
    public static func completionAdvance(_ it: ResolvedItem, now: Date, calendar: Calendar = .current) -> [String: String]? {
        guard let u = unit(it), let dueStr = it.due, let dueDate = ItemSchedule.parseDay(dueStr, calendar: calendar) else { return nil }
        let pivot = max(now, dueDate)
        var o = dueDate, k = 0
        while o <= pivot, k < 100_000 { o = step(o, by: u, calendar: calendar); k += 1 }
        guard k > 0 else { return nil }
        return advanceBy(it, steps: k, dueDate: dueDate, dueStr: dueStr, unit: u, now: now, calendar: calendar)
    }

    /// 항목의 **놓친 회차 수**(편의) — 앵커 = 마감(회차). 되풀이 아니거나 앵커 없으면 0.
    ///
    /// **꺼둔 동안은 세지 않는다(2026-08-03).** 꺼두기는 "세지 않겠다"는 뜻인데 2주 꺼뒀다 켜면
    /// "14일 놓침"이 붙는 건 안 놓친 것을 놓쳤다고 하는 것이다. 꺼둠이면 `now` 대신 **꺼둔 시점**까지만 센다
    /// → 꺼두기 전에 이미 쌓인 놓침은 **그대로 보존**되고 그 뒤로는 안 늘어난다.
    /// 켤 때 `resumeChanges`가 꺼둔 기간만큼 회차를 전진시켜 **경계에서 숫자가 튀지 않는다**(아래 증명).
    ///
    /// 꺼둠인데 `recurPausedAt`이 없으면(이 변경 전에 꺼둔 것) `now`로 폴백 — 옛 동작 그대로, 안전한 강등.
    public static func missed(_ it: ResolvedItem, now: Date, calendar: Calendar = .current) -> Int {
        guard it.type == "recurrence", let u = unit(it),
              let dueStr = it.due, let base = ItemSchedule.parseDay(dueStr, calendar: calendar) else { return 0 }
        let cutoff = isPaused(it) ? (pausedAt(it, calendar: calendar) ?? now) : now
        return missedCount(base: base, unit: u, now: cutoff, calendar: calendar)
    }

    /// 꺼둔 시점(없거나 못 읽으면 nil).
    public static func pausedAt(_ it: ResolvedItem, calendar: Calendar = .current) -> Date? {
        it.fields[pausedAtKey].flatMap { ItemSchedule.parseDay($0, calendar: calendar) }
    }

    /// **켤 때 회차 전진 changes** — 꺼둔 기간에 지나간 회차만큼 마감을 전진시키고 `recurPausedAt`을 비운다.
    /// 안 켜졌거나(아직 꺼둠) 꺼둔 기록이 없으면 nil(멱등 — 전진 뒤 재실행하면 필드가 비어 더 안 바뀐다).
    ///
    /// **전진량 k = (지금까지의 놓침) − (꺼둘 때의 놓침).** 즉 꺼둔 구간에 들어간 회차 수만 건너뛴다.
    /// 그래서 켠 뒤 놓침 = `missedCount(마감+k, now)` = `m_now − k` = **꺼둘 때의 놓침**(정확히 보존).
    /// 첫 미래 회차로 점프시키면 이전 놓침까지 지워지므로 **그렇게 하지 않는다** — 꺼두기는 사면이 아니다.
    /// 미리 알림도 같은 k만큼 전진(lead 보존) — `advanceBy` 공용.
    ///
    /// 자동완성이 있으면 이 전진 뒤 같은 로드의 `catchUpChanges`가 현재까지 더 전진시켜 놓침이 0이 된다.
    /// 그건 자동완성의 뜻("완료 안 해도 닫힌다")이 원래 그런 것이라 꺼두기와 무관하게 일관적이다.
    public static func resumeChanges(_ it: ResolvedItem, now: Date, calendar: Calendar = .current) -> [String: String]? {
        guard it.type == "recurrence", !isPaused(it),                       // 켜져 있어야(=막 켰거나 켠 상태)
              let pausedDate = pausedAt(it, calendar: calendar),            // 꺼둔 기록이 남아 있어야
              let u = unit(it), let dueStr = it.due,
              let dueDate = ItemSchedule.parseDay(dueStr, calendar: calendar) else { return nil }
        let k = missedCount(base: dueDate, unit: u, now: now, calendar: calendar)
              - missedCount(base: dueDate, unit: u, now: pausedDate, calendar: calendar)
        var changes: [String: String] = [pausedAtKey: ""]                   // 기록 비움(멱등 종료 조건)
        if k > 0 {
            changes.merge(advanceBy(it, steps: k, dueDate: dueDate, dueStr: dueStr, unit: u, now: now, calendar: calendar)) { _, new in new }
        }
        return changes
    }

    /// **catch-up(앱 열 때) 회차 전진 changes** — 자동 완성 있으면 지난 회차 자동 완성(마감·미리 알림 전진),
    /// `none`이면 안 함(쌓임). 변화 없으면 nil(멱등).
    /// 자동완성 임계: 정오=그 날 12시, 지나면=그 날 끝(다음 자정) — 단 **회차 시각보다 앞설 수 없다**(아래 `threshold`).
    /// **꺼둠(`isDormant`)이면 안 한다** — 꺼둔 동안 회차가 조용히 흘러가면 켰을 때 이미 다 지나간 상태가 된다.
    /// 마감이 꺼둔 시점 회차에 얼어 있다가, 켜면 그때 밀린 만큼 한 번에 전진한다(멱등, 데이터 손상 없음).
    public static func catchUpChanges(_ it: ResolvedItem, now: Date, calendar: Calendar = .current) -> [String: String]? {
        let auto = autoComplete(it)
        guard !isDormant(it), auto != .none, let u = unit(it), let dueStr = it.due, let dueDate = ItemSchedule.parseDay(dueStr, calendar: calendar) else { return nil }
        /// 이 회차가 "넘어간" 것으로 볼 시점. **회차가 오기도 전에 넘어갈 수는 없다**(Stage 5-0, 2026-08-04)
        /// → 임계는 **회차 시각(`o`)보다 앞설 수 없다**. 안 막으면 `noon` + 저녁 마감에서 임계(12시)가
        /// 마감(20시)보다 앞서서 **회차가 도착하기도 전에 닫히고**, 정작 20시에 이미 닫힌 회차로 알림이 간다.
        /// 이 보정으로 저녁 마감 + `noon`은 `endOfDay`처럼(마감 시각 이후에) 동작하고,
        /// **아침 마감·날짜만 있는 항목은 전혀 안 바뀐다**(`max(12:00, 08:00) = 12:00`, `max(12:00, 00:00) = 12:00`).
        /// `endOfDay`는 임계(다음 자정)가 언제나 그 날 회차 시각보다 뒤라 `max`가 no-op이다.
        func threshold(_ o: Date) -> Date {
            let d0 = calendar.startOfDay(for: o)
            let base = auto == .noon ? (calendar.date(byAdding: .hour, value: 12, to: d0) ?? d0)
                                     : (calendar.date(byAdding: .day, value: 1, to: d0) ?? d0)
            return max(base, o)
        }
        var o = dueDate, k = 0
        while threshold(o) <= now, k < 100_000 { o = step(o, by: u, calendar: calendar); k += 1 }
        guard k > 0 else { return nil }
        return advanceBy(it, steps: k, dueDate: dueDate, dueStr: dueStr, unit: u, now: now, calendar: calendar)
    }

    /// 반복 주기(설정 안 됐거나 모르는 값이면 nil).
    public static func unit(_ it: ResolvedItem) -> Unit? {
        it.fields[unitKey].flatMap(Unit.init(rawValue:))
    }
    /// 자동 완성(없거나 모르는 값이면 none).
    public static func autoComplete(_ it: ResolvedItem) -> AutoComplete {
        it.fields[autoKey].flatMap(AutoComplete.init(rawValue:)) ?? .none
    }
    /// 꺼둠 여부(잠시 멈춤 — §5의 "그만두기(삭제)"와 구분).
    public static func isPaused(_ it: ResolvedItem) -> Bool {
        it.fields[pausedKey] == "true"
    }

    /// **꺼둔 되풀이 = 시점 없는 것으로 취급**(2026-08-03). 상세 배너가 "알림·되살아나기 멈춤"이라고
    /// 약속하는데 정작 세 경로에 가드가 없어 셋 다 안 지켜지고 있었다 — 그 약속을 코드로 만든 술어다.
    /// 세 소비처가 각자 이걸 호출한다: 알림(`NotificationPlanner.plan`)·게시 게이트(`ItemSchedule.isPublished`)·
    /// 자동완성 catch-up(`catchUpChanges`, 아래).
    ///
    /// **뜻은 여기 한 곳, 가드는 세 곳에 명시**한다. 게이트를 `publishDay`에 심어 상속시키는 방법도 되지만
    /// (소비처가 planner·sectionizer 둘뿐이라) **Stage 5가 알림 경로에서 `publishDay`를 걷어내므로**
    /// 그러면 가드가 그때 조용히 사라진다. 꺼두기는 *날짜 역할*이 아니라 *항목 상태*라 층이 다르기도 하다.
    ///
    /// 되풀이가 아니면 절대 걸리지 않는다 — 다른 분류에 `recurPaused`가 남아 있어도 무시(오염 차단).
    /// 필드 없음·`"false"`도 전부 통과하므로 **기존 항목 동작은 변하지 않는다.**
    public static func isDormant(_ it: ResolvedItem) -> Bool {
        it.type == "recurrence" && isPaused(it)
    }
}
