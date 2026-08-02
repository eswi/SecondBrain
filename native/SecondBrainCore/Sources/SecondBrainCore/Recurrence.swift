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
    public static let lastDoneKey = "lastDone"   // 마지막 완료 시점(시각 표준형 T)

    /// 마지막 완료 시점(없거나 못 읽으면 nil). 형식 = 시각 표준형 "YYYY-MM-DD'T'HH:mm".
    public static func lastDone(_ it: ResolvedItem, calendar: Calendar = .current) -> Date? {
        it.fields[lastDoneKey].flatMap { ItemSchedule.parseDay($0, calendar: calendar) }
    }

    /// **오늘 이미 완료했나 (Stage 3 최소판)** — 마지막 완료 시점의 날이 오늘이면 true.
    /// "오늘 약 먹었나"에 답한다(매일 약). 주기별 정확한 회차 창(매주·매년)은 Stage 4.
    public static func doneToday(_ it: ResolvedItem, now: Date, calendar: Calendar = .current) -> Bool {
        guard let d = lastDone(it, calendar: calendar) else { return false }
        return calendar.isDate(d, inSameDayAs: now)
    }

    /// **완료 버튼이 낼 이벤트 필드 — 분류로 분기(§5, Stage 3의 핵심).**
    /// - 되풀이 → **마지막 완료 시점만 기록**(status 안 건드림 → 항목이 살아있음, 안 사라짐).
    /// - 그 외 → **status=done**(영구 종료·보관함행 — 기존 동작 그대로).
    public static func completionChanges(for it: ResolvedItem, now: Date, calendar: Calendar = .current) -> [String: String] {
        guard it.type == "recurrence" else { return ["status": "done"] }
        var c = [lastDoneKey: ItemSchedule.dayTimeString(now, calendar: calendar)]
        if let adv = completionAdvance(it, now: now, calendar: calendar) {
            c.merge(adv) { _, new in new }   // 마감(회차)·미리 알림을 다음 회차로 → 게시 게이트가 즉시 숨긴다(#1·#2)
        }
        return c
    }

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
    private static func advanceBy(_ it: ResolvedItem, steps k: Int, dueDate: Date, dueStr: String, unit u: Unit, calendar: Calendar) -> [String: String] {
        var changes: [String: String] = [:]
        var od = dueDate; for _ in 0..<k { od = step(od, by: u, calendar: calendar) }
        changes["due"] = formatLike(od, source: dueStr, calendar: calendar)
        if let rStr = it.resurface, let rDate = ItemSchedule.parseDay(rStr, calendar: calendar) {
            var or = rDate; for _ in 0..<k { or = step(or, by: u, calendar: calendar) }
            changes["resurface"] = formatLike(or, source: rStr, calendar: calendar)
        }
        return changes
    }

    /// **완료 시 회차 전진** — 마감을 `max(now, 현재 마감)` 이후 첫 회차로, 미리 알림도 같은 간격 전진(lead 보존).
    /// 온타임·이른·밀린 경우 다 다음 미래 회차로 넘어가 게이트가 즉시 숨긴다(#1·#2). 앵커(마감) 없으면 nil.
    public static func completionAdvance(_ it: ResolvedItem, now: Date, calendar: Calendar = .current) -> [String: String]? {
        guard let u = unit(it), let dueStr = it.due, let dueDate = ItemSchedule.parseDay(dueStr, calendar: calendar) else { return nil }
        let pivot = max(now, dueDate)
        var o = dueDate, k = 0
        while o <= pivot, k < 100_000 { o = step(o, by: u, calendar: calendar); k += 1 }
        guard k > 0 else { return nil }
        return advanceBy(it, steps: k, dueDate: dueDate, dueStr: dueStr, unit: u, calendar: calendar)
    }

    /// 항목의 **놓친 회차 수**(편의) — 앵커 = 마감(회차). 되풀이 아니거나 앵커 없으면 0.
    public static func missed(_ it: ResolvedItem, now: Date, calendar: Calendar = .current) -> Int {
        guard it.type == "recurrence", let u = unit(it),
              let dueStr = it.due, let base = ItemSchedule.parseDay(dueStr, calendar: calendar) else { return 0 }
        return missedCount(base: base, unit: u, now: now, calendar: calendar)
    }

    /// **catch-up(앱 열 때) 회차 전진 changes** — 자동 완성 있으면 지난 회차 자동 완성(마감·미리 알림 전진),
    /// `none`이면 안 함(쌓임). 변화 없으면 nil(멱등). 자동완성 임계: 정오=그 날 12시, 지나면=그 날 끝(다음 자정).
    public static func catchUpChanges(_ it: ResolvedItem, now: Date, calendar: Calendar = .current) -> [String: String]? {
        let auto = autoComplete(it)
        guard auto != .none, let u = unit(it), let dueStr = it.due, let dueDate = ItemSchedule.parseDay(dueStr, calendar: calendar) else { return nil }
        func threshold(_ o: Date) -> Date {
            let d0 = calendar.startOfDay(for: o)
            return auto == .noon ? (calendar.date(byAdding: .hour, value: 12, to: d0) ?? d0)
                                 : (calendar.date(byAdding: .day, value: 1, to: d0) ?? d0)
        }
        var o = dueDate, k = 0
        while threshold(o) <= now, k < 100_000 { o = step(o, by: u, calendar: calendar); k += 1 }
        guard k > 0 else { return nil }
        return advanceBy(it, steps: k, dueDate: dueDate, dueStr: dueStr, unit: u, calendar: calendar)
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
}
