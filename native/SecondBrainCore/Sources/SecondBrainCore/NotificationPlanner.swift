import Foundation

/// 로컬 알림 계획 한 건.
public struct PlannedNotification: Equatable, Sendable {
    /// **어느 지점의 알림인가**(Stage 5-A, 2026-08-04). 한 항목이 **최대 두 건**을 낸다.
    /// 두 칸의 역할이 갈렸으므로(미리 알림 = 게시 시작 / 마감 = 기한) 알림도 두 지점에서 울려야 한다 —
    /// 한 지점만 쓰던 게 **lead-time 구멍**이었다(7시 미리 알림 + 8시 약이 7시만 울림, §9).
    public enum Kind: String, Sendable, Equatable {
        case lead   // 미리 알림(게시 시작) — "곧"
        case due    // 마감/회차 시각 — "지금"
        /// 정렬 결정성용. 접힘 규칙 때문에 같은 항목·같은 시각으로 둘이 겹치는 일은 없다(방어).
        var order: Int { self == .lead ? 0 : 1 }
    }

    public let id: String        // 항목 id
    public let kind: Kind        // 두 지점 중 어디
    public let fireDate: Date    // 울릴 시각
    public let title: String
    public let body: String
    /// **어느 회차인가**(체인, Stage 5-C) — 그 회차의 마감 날짜("YYYY-MM-DD"). 체인이 아닌 건 nil.
    /// 식별자를 가르는 데만 쓴다 — 한 항목이 여러 회차를 내므로 종류만으로는 안 갈린다.
    public let cycleKey: String?

    public init(id: String, kind: Kind, fireDate: Date, title: String, body: String, cycleKey: String? = nil) {
        self.id = id; self.kind = kind; self.fireDate = fireDate
        self.title = title; self.body = body; self.cycleKey = cycleKey
    }

    /// 시스템 알림 식별자의 항목 부분(접두어 `sb:`는 앱이 붙인다).
    /// **한 항목이 여러 건을 내므로 종류·회차까지 넣어야 한다** — 안 갈면 뒤의 등록이 앞의 것을 덮어쓴다.
    /// 회차가 없으면(일반 항목·체인 아님) 옛 형식 `<id>:<kind>` 그대로 — 전량 재등록이라 형식이 섞여도 무해하다.
    public var requestKey: String {
        cycleKey.map { "\(id):\($0):\(kind.rawValue)" } ?? "\(id):\(kind.rawValue)"
    }
}

/// **알림 예산**(Stage 5-B, 2026-08-04) — iOS 대기 알림 한도 **64**를 반복·일반이 공유한다.
/// 목적은 정확한 숫자가 아니라 **"반복이 일반을 조용히 밀어내지 않는다"**.
/// 옛 모델은 `fireDate` 하나로 정렬해 앞에서 32개를 잘랐다 → 반복은 다음 발화가 늘 임박해 **정렬 최상위를
/// 점거**하고, 2주 뒤 마감인 일반 항목이 조용히 밀려났다. 그래서 **두 몫을 독립 상한**으로 나눈다.
public struct NotificationBudget: Equatable, Sendable {
    public let total: Int        // 총 상한 — 64에 마진을 둔다(초과 시 iOS 동작이 미확정이라 안 닿게 한다)
    public let recurring: Int    // 반복 몫(하한 보장)
    public let plain: Int        // 일반 몫(하한 보장 — 반복이 잠식 못 함)
    public init(total: Int, recurring: Int, plain: Int) {
        self.total = total; self.recurring = recurring; self.plain = plain
    }
    /// 64 중 48만 쓰고 16 마진, 반씩(24/24).
    public static let standard = NotificationBudget(total: 48, recurring: 24, plain: 24)
}

/// 계획 결과 + **예산 회계**. 잘린 것이 조용히 사라지지 않게 개수를 같이 돌려준다(5-B 요구).
/// 알림은 **안 오는 것을 눈치채기 어려워** 특히 위험하다 — 그래서 "몇 개 잘렸나"가 값으로 나와야 한다.
public struct NotificationPlanResult: Equatable, Sendable {
    public let scheduled: [PlannedNotification]
    public let usedRecurring: Int          // 반복이 쓴 슬롯
    public let usedPlain: Int              // 일반이 쓴 슬롯
    public let borrowedFromPlain: Int      // 반복이 일반의 남는 몫에서 빌린 슬롯(단방향)
    public let droppedRecurringCycles: Int // 예산 때문에 등록 못 한 **회차 묶음** 수(반복)
    public let droppedPlainCycles: Int     // 같은 것(일반)
    public let droppedSlots: Int           // 그 묶음들이 요구했던 슬롯 합
    /// **라운드 1에서 잘린 묶음 수 = 진짜 손실**(Stage 5-C, 2026-08-06).
    ///
    /// 체인은 예산을 끝까지 쓰므로 **마지막 라운드는 거의 항상 잘린다.** 그래서 `droppedCycles`를 그대로
    /// 경고로 쓰면 ⚠️가 상시 켜져 **신호가 죽는다.** 둘은 뜻이 완전히 다르다:
    /// - **라운드 1 잘림** = 그 항목은 **다음 회차 알림이 아예 없다**(옛 모델에서의 잘림과 같은 것).
    /// - **라운드 2+ 잘림** = 체인이 짧아진 것뿐. 다음에 앱을 열면 다시 계산된다 — 정상 상태다.
    public let droppedFirstRoundCycles: Int

    public var droppedCycles: Int { droppedRecurringCycles + droppedPlainCycles }
    public var used: Int { usedRecurring + usedPlain }

    /// 사람이 읽는 한 줄 — 로그·디버그 화면 공용. **확인 경로**가 이걸로 하나로 모인다.
    /// ⚠️는 **라운드 1 잘림에만** 켠다(위 참조). 체인 길이가 줄어든 것은 괄호 안에 조용히 적는다.
    public var summary: String {
        var s = "알림 \(used)건(반복 \(usedRecurring)/일반 \(usedPlain))"
        if borrowedFromPlain > 0 { s += " · 대여 \(borrowedFromPlain)" }
        if droppedFirstRoundCycles > 0 {
            s += " · ⚠️알림 없음 \(droppedFirstRoundCycles)항목(반복 \(droppedRecurringCycles)/일반 \(droppedPlainCycles) 회차 잘림, \(droppedSlots)건)"
        } else if droppedCycles > 0 {
            s += " · 체인 축소 \(droppedCycles)회차(\(droppedSlots)건)"
        }
        return s
    }
}

/// push(시점 알림)의 순수 로직: 받은함 항목 → "언제 울릴지" 계획.
///
/// **두 지점에서 울린다**(Stage 5-A) — **미리 알림(lead, "곧")** 과 **마감/회차(due, "지금")**.
/// 분류 게이트는 `ItemSchedule`이 상속시킨다(`gatedResurface`·`deadlineDay`) — 그 분류가 안 쓰는 칸은 지점이 아니다.
/// - **lead 0 접힘:** 미리 알림이 없거나 마감과 **같은 시각**이면 한 건(마감)으로 접는다. 안 접으면 예산이 이유 없이 2배.
/// - **알려주는 알림은 한 건만:** 자동 완성이 있는 되풀이(생일)는 완료를 요구하지 않으므로 두 번 찌를 이유가 없다.
///   lead가 있으면 lead(미리 알아야 쓸모가 있다 — 선물·연락), 없으면 회차.
/// - **되풀이 특례가 아니다** — 일반 항목도 두 지점을 받는다. 미리 알림만 걸었을 때 정작 마감일에 조용한 건
///   되풀이만의 문제가 아니었다.
/// - **꺼둔 되풀이는 아무 건도 안 낸다**(`Recurrence.isDormant`).
///
/// 과거 시점은 제외(앱 안 '지금 챙길 것'이 담당), 미래만.
/// 정렬은 (시각, id, 종류)로 **완전 결정적** — 상한에 걸릴 때 무엇이 남는지가 흔들리지 않게.
/// 배분은 `NotificationBudget`(반복/일반 분리 + 라운드로빈 + 단방향 대여, 5-B) — `planned(...)` 참조.
///
/// **문구는 세 톤**(Stage 5-D, 2026-08-06) — 「곧 챙길 것」/「지금 챙길 것」/「오늘 기억할 것」. `title(kind:telling:)` 참조.
/// 본문(body)은 **원문 그대로**다 — 알림이 기억 자체를 보여준다(요약·가공 안 함).
///
/// **체인(Stage 5-C, 2026-08-06)** — 되풀이는 항목당 **다음 K회차**를 미리 낸다(`chainBundles`).
/// 호라이즌 = **시간 창 `now + horizonDays`(기본 7) × 예산**. 회차 수로 자르지 않는 이유는 §9 Stage 5-C 참조:
/// 되풀이가 적으면 예산만으로는 체인이 한 달 치까지 뻗어 **stale 알림 위험이 그만큼 커지고**,
/// 라운드 수로 자르면 매년 항목이 몇 년 치를 건다. 시간 창이면 주기가 제 몫을 한다
/// (매일 = D회차 / 매주·매년 = 1회차 = 옛 동작 그대로).
public enum NotificationPlanner {
    /// 체인 시간 창(일). **뚜껑일 뿐 — 실제로 먼저 닿는 것은 예산인 경우가 많다**(§9 Stage 5-C 표).
    public static let defaultHorizonDays = 7
    /// 폭주 방어. 주기가 일/주/년뿐이라 실제로는 `horizonDays + 1`을 안 넘는다.
    private static let maxCyclesPerItem = 366

    /// 편의 — 계획된 알림만. 회계까지 필요하면 `planned(...)`.
    public static func plan(items: [ResolvedItem], now: Date,
                            calendar: Calendar = .current, hour: Int = 9,
                            budget: NotificationBudget = .standard,
                            horizonDays: Int = NotificationPlanner.defaultHorizonDays) -> [PlannedNotification] {
        planned(items: items, now: now, calendar: calendar, hour: hour,
                budget: budget, horizonDays: horizonDays).scheduled
    }

    /// 계획 + 예산 회계(5-B).
    ///
    /// **회차 묶음이 배분 단위다.** 한 회차의 lead·회차 지점(1~2건)을 **통째로** 넣거나 통째로 뺀다.
    /// 건 단위로 쪼개 넣으면 "곧"만 오고 "지금"이 안 오는 항목이 생겨 **5-A에서 닫은 lead-time 구멍이
    /// 예산 때문에 다시 열린다 — 그것도 조용히.**
    ///
    /// **라운드로빈**: 라운드 n = 각 항목의 n번째 회차 묶음. 라운드 안에서는 이른 순(+id)로 결정적.
    /// 이른 순으로만 채우면 하루 N회 항목이 몫을 점거해 매주·매년이 영구히 밀리므로, 라운드로빈으로
    /// **어떤 항목도 0회차가 되지 않게** 한다. (5-B는 항목당 1묶음이라 라운드가 1개 — 여러 묶음은 5-C.)
    ///
    /// **단방향 대여**: 일반이 자기 몫을 안 쓰면 남은 걸 반복이 빌려 호라이즌을 늘린다.
    /// **일반의 몫은 항상 보장**(반복이 잠식 못 함) — 그게 이 스테이지의 목적이다.
    public static func planned(items: [ResolvedItem], now: Date,
                               calendar: Calendar = .current, hour: Int = 9,
                               budget: NotificationBudget = .standard,
                               horizonDays: Int = NotificationPlanner.defaultHorizonDays) -> NotificationPlanResult {
        var recurringQueues: [[Bundle]] = []
        var plainQueues: [[Bundle]] = []
        for it in items {
            if Recurrence.isDormant(it) { continue }   // 꺼둔 되풀이는 알림 안 냄(배너 약속, 2026-08-03)
            if it.type == "recurrence" {
                // 체인(5-C) — 다음 K회차. 주기·앵커가 없으면 안에서 옛 경로(현재 회차 1개)로 떨어진다.
                let chain = chainBundles(it, now: now, calendar: calendar, hour: hour, horizonDays: horizonDays)
                if !chain.isEmpty { recurringQueues.append(chain) }
            } else {
                guard let b = cycleBundle(it, now: now, calendar: calendar, hour: hour) else { continue }
                plainQueues.append([b])
            }
        }

        // 일반 먼저 — 반복이 빌릴 수 있는 남은 몫을 알아야 한다(단방향이라 일반은 반복에 의존하지 않는다).
        let plainFill = roundRobin(plainQueues, budget: min(budget.plain, budget.total))
        let leftover = max(0, budget.plain - plainFill.used)
        // 총량도 넘지 않게: 대여를 더해도 total − 일반사용분을 넘길 수 없다.
        let recurBudget = min(budget.recurring + leftover, budget.total - plainFill.used)
        let recurFill = roundRobin(recurringQueues, budget: recurBudget)

        let scheduled = (plainFill.placed + recurFill.placed)
            .flatMap(\.points)
            .sorted { a, b in
                if a.fireDate != b.fireDate { return a.fireDate < b.fireDate }
                if a.id != b.id { return a.id < b.id }
                return a.kind.order < b.kind.order
            }
        return NotificationPlanResult(
            scheduled: scheduled,
            usedRecurring: recurFill.used,
            usedPlain: plainFill.used,
            borrowedFromPlain: max(0, recurFill.used - budget.recurring),
            droppedRecurringCycles: recurFill.dropped.count,
            droppedPlainCycles: plainFill.dropped.count,
            droppedSlots: (recurFill.dropped + plainFill.dropped).reduce(0) { $0 + $1.slots },
            droppedFirstRoundCycles: recurFill.droppedFirstRound + plainFill.droppedFirstRound)
    }

    /// 한 항목의 **한 회차 묶음** — 예산 배분의 최소 단위(쪼개지 않는다).
    private struct Bundle {
        let itemId: String
        let isRecurring: Bool
        let points: [PlannedNotification]
        var slots: Int { points.count }
        /// 라운드 안 정렬 키 — 이 묶음이 가장 먼저 울리는 시각.
        var earliest: Date { points.map(\.fireDate).min() ?? .distantFuture }
    }

    /// 라운드로빈 채우기. 예산에 안 들어간 묶음은 **전부 `dropped`로 센다** — 조용히 사라지지 않게.
    /// (앞 묶음이 안 들어갔는데 뒤의 더 작은 묶음이 들어갈 수는 있다. 결정적이고, 총량을 더 쓰는 쪽이 이득.)
    ///
    /// **`droppedFirstRound`를 따로 센다**(5-C) — 라운드 1 잘림만이 "그 항목에 다음 알림이 아예 없다"는 뜻이다.
    /// 체인이 들어오면 마지막 라운드는 거의 항상 잘리므로, 안 가르면 경고가 상시 켜져 무의미해진다.
    private static func roundRobin(_ queues: [[Bundle]], budget: Int)
        -> (placed: [Bundle], dropped: [Bundle], droppedFirstRound: Int, used: Int) {
        var placed: [Bundle] = [], dropped: [Bundle] = [], used = 0, droppedFirstRound = 0
        let maxRound = queues.map(\.count).max() ?? 0
        for round in 0..<maxRound {
            let ordered = queues.compactMap { round < $0.count ? $0[round] : nil }
                .sorted { $0.earliest != $1.earliest ? $0.earliest < $1.earliest : $0.itemId < $1.itemId }
            for b in ordered {
                if used + b.slots <= budget {
                    placed.append(b); used += b.slots
                } else {
                    dropped.append(b)
                    if round == 0 { droppedFirstRound += 1 }
                }
            }
        }
        return (placed, dropped, droppedFirstRound, used)
    }

    /// 항목의 현재 회차 묶음(미래 지점만). 낼 게 없으면 nil. — 일반 항목과 체인 못 하는 되풀이의 경로.
    private static func cycleBundle(_ it: ResolvedItem, now: Date,
                                   calendar: Calendar, hour: Int) -> Bundle? {
        makeBundle(it, dueStr: ItemSchedule.deadlineDay(it), leadStr: ItemSchedule.gatedResurface(it),
                   cycleKey: nil, now: now, calendar: calendar, hour: hour)
    }

    /// **한 회차의 묶음을 만든다** — 날짜 문자열 두 개(마감·미리 알림)에서. 현재 회차든 체인의 n번째 회차든 같은 몸통.
    /// 접힘·알려주기 규칙이 **회차마다 똑같이** 적용돼야 하므로 한 곳에 둔다.
    private static func makeBundle(_ it: ResolvedItem, dueStr: String?, leadStr: String?, cycleKey: String?,
                                   now: Date, calendar: Calendar, hour: Int) -> Bundle? {
        let leadFire = leadStr.flatMap { fireInstant($0, calendar: calendar, hour: hour) }
        let dueFire  = dueStr.flatMap  { fireInstant($0, calendar: calendar, hour: hour) }

        var points: [(kind: PlannedNotification.Kind, fire: Date)] = []
        if let d = dueFire { points.append((.due, d)) }
        // lead 0 접힘 — 마감과 같은 시각이면 안 넣는다. 마감이 없으면(nil) lead만 남는다.
        if let l = leadFire, l != dueFire { points.append((.lead, l)) }

        if notifyOnly(it), points.count > 1 {
            // 알려주는 알림은 한 건만 — lead 우선(미리 알아야 쓸모가 있다).
            points = points.filter { $0.kind == .lead }
        }

        let telling = notifyOnly(it)
        let planned = points.filter { $0.fire > now }.map {   // 미래만
            PlannedNotification(id: it.id, kind: $0.kind, fireDate: $0.fire,
                                title: title(kind: $0.kind, telling: telling),
                                body: it.raw ?? "(항목)",   // 원문 그대로 — 알림이 기억 자체를 보여준다
                                cycleKey: cycleKey)
        }
        guard !planned.isEmpty else { return nil }
        return Bundle(itemId: it.id, isRecurring: it.type == "recurrence", points: planned)
    }

    /// **체인(Stage 5-C) — 되풀이의 다음 K회차 묶음.**
    ///
    /// ### ★ 여기서 회차를 전진시키지만 **저장하지 않는다**
    /// 이건 알림 계획만의 계산이다. 이 전진이 이벤트로 나가면 **놓침이 사라져 자동완성 "없음"의 뜻이 깨진다**
    /// — "약을 3일 놓친 것"이 이 설계의 출발점인데 그게 무너진다. `NotificationPlanner`는 순수 함수라
    /// 구조적으로 쓸 수단이 없고, 회귀선이 그것을 못박는다(`NotificationChainTests`).
    ///
    /// ### 지난 회차는 건너뛴다 = 구멍 1이 닫히는 자리
    /// 자동완성 없는 약은 마감이 안 전진하므로 **미래 지점이 없어 알림이 영구히 끊겼다**(2026-08-04 실측:
    /// 되풀이 3개 중 2개가 슬롯 0). 첫 **미래** 회차부터 시작하면 내일·모레 회차가 들어가 되살아난다.
    /// 건너뛸 때 **묶음의 마지막 지점**을 기준으로 본다 — 미리 알림이 마감보다 뒤인 어긋난 값(손편집으로
    /// 실제로 생겼다, §5 미결)에서도 살아 있는 회차를 흘리지 않게.
    ///
    /// ### 창 = 회차 앵커(마감) 기준, 단 **첫 회차는 창 밖이어도 반드시 낸다**
    /// 안 그러면 매주·매년 항목이 **0회차**가 된다(옛 동작에서 후퇴). 라운드로빈의 "어떤 항목도 0회차가
    /// 되지 않는다"와 같은 약속을 창에서도 지킨다.
    private static func chainBundles(_ it: ResolvedItem, now: Date, calendar: Calendar,
                                     hour: Int, horizonDays: Int) -> [Bundle] {
        // 주기·앵커가 없으면 회차가 정의되지 않는다 → 옛 경로(현재 회차 하나)로.
        guard let u = Recurrence.unit(it),
              let dueStr = ItemSchedule.deadlineDay(it),
              let dueBase = ItemSchedule.parseDay(dueStr, calendar: calendar),
              let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: now)
        else { return cycleBundle(it, now: now, calendar: calendar, hour: hour).map { [$0] } ?? [] }

        let leadStr = ItemSchedule.gatedResurface(it)
        let leadBase = leadStr.flatMap { ItemSchedule.parseDay($0, calendar: calendar) }

        // 이 항목이 실제로 **내보내는** 지점의 마지막 것 — 건너뛰기 기준.
        // 알려주기(자동완성 있음)는 lead 하나만 내므로 마감이 미래여도 그 회차는 낼 게 없다.
        let leadOnly = notifyOnly(it) && leadBase != nil && leadBase != dueBase
        var tail = leadOnly ? (leadBase ?? dueBase) : max(dueBase, leadBase ?? dueBase)
        var skipped = 0
        while tail <= now, skipped < 100_000 {
            tail = Recurrence.step(tail, by: u, calendar: calendar)
            skipped += 1
        }

        var out: [Bundle] = []
        for n in 0..<maxCyclesPerItem {
            let i = skipped + n
            let dueDate = stepped(dueBase, by: u, times: i, calendar: calendar)
            if !out.isEmpty, dueDate > horizonEnd { break }   // 창 밖 — 단 첫 회차는 위 규칙대로 통과시킨다
            let cycleKey = ItemSchedule.dayString(dueDate, calendar: calendar)
            let dueS = sameShape(dueDate, as: dueStr, calendar: calendar)
            let leadS = zip2(leadStr, leadBase).map {
                sameShape(stepped($0.1, by: u, times: i, calendar: calendar), as: $0.0, calendar: calendar)
            }
            if let b = makeBundle(it, dueStr: dueS, leadStr: leadS, cycleKey: cycleKey,
                                  now: now, calendar: calendar, hour: hour) {
                out.append(b)
            }
            if !out.isEmpty, dueDate > horizonEnd { break }   // 첫 회차가 창 밖이었던 경우 여기서 멈춘다
        }
        return out
    }

    /// `date`를 주기만큼 `times`회 전진(0이면 그대로).
    private static func stepped(_ date: Date, by u: Recurrence.Unit, times: Int, calendar: Calendar) -> Date {
        var d = date
        for _ in 0..<times { d = Recurrence.step(d, by: u, calendar: calendar) }
        return d
    }

    /// `date`를 **원본 문자열과 같은 형식**으로. 시각이 있던 값은 시각을 유지하고, 날짜만이던 값은 날짜만
    /// (→ `fireInstant`의 `hour` 폴백이 그대로 걸린다). 회차마다 발화 시각이 흔들리지 않게 하는 장치.
    private static func sameShape(_ date: Date, as source: String, calendar: Calendar) -> String {
        ItemSchedule.timeOfDay(source) != nil ? ItemSchedule.dayTimeString(date, calendar: calendar)
                                              : ItemSchedule.dayString(date, calendar: calendar)
    }

    /// 둘 다 있을 때만 쌍으로. (Optional 두 개를 한 번에 여는 작은 도우미.)
    private static func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
        guard let a, let b else { return nil }
        return (a, b)
    }

    /// **알림 제목 — 세 톤**(Stage 5-D, 2026-08-06. 문구는 사용자가 정했다).
    ///
    /// | 톤 | 문구 | 언제 |
    /// |---|---|---|
    /// | 재촉 · 예고 | **곧 챙길 것** | 완료를 요구하는 항목의 미리 알림(lead) |
    /// | 재촉 · 지금 | **지금 챙길 것** | 완료를 요구하는 항목의 마감/회차 |
    /// | 통보 | **오늘 기억할 것** | 완료를 안 요구하는 것(자동 완성이 있는 되풀이 — 생일·기일) |
    ///
    /// **"챙기다" = 재촉 / "기억하다" = 통보**로 갈리고, `…것` 어법과 핵심어 "기억"을 유지한다.
    ///
    /// **★ 옛 제목 `"받은함 · 곧 닥칠 것"`은 화면에 없는 말이 둘이었다.**
    /// - **"받은함"** — 탭 이름은 **"새로운 기억"** 이다. 코드·프롬프트에만 사는 옛말이 알림으로 새어 나왔다.
    /// - **"곧 닥칠 것"** — 섹션 이름은 **"지금 챙길 것"** 이다. 2026-08-03에 Core 주석의 같은 오용을
    ///   정정했는데 **정작 사용자 눈에 닿는 이 문자열이 남아 있었다**(주석은 고치고 화면은 안 고친 꼴).
    ///
    /// **「지금 챙길 것」은 섹션 이름과 일부러 같다** — 알림을 탭했을 때 갈 곳의 이름과 맞춘 것이다.
    /// ⚠️ **다만 지금은 탭해도 그리로 안 간다**(§9 미결 "알림 탭 착지" 참조). 문구가 약속을 앞서 있다.
    private static func title(kind: PlannedNotification.Kind, telling: Bool) -> String {
        if telling { return "오늘 기억할 것" }        // 통보 — lead든 회차든 한 건뿐이라 종류를 안 본다
        return kind == .lead ? "곧 챙길 것" : "지금 챙길 것"
    }

    /// **알려주는 알림**(완료를 요구하지 않는 것) = 자동 완성이 있는 되풀이. 생일이 대표.
    /// 완료를 안 해도 회차가 닫히므로 "곧" + "지금" 두 번 찌를 이유가 없다(결정 2026-08-03).
    private static func notifyOnly(_ it: ResolvedItem) -> Bool {
        it.type == "recurrence" && Recurrence.autoComplete(it) != .none
    }

    /// 날짜 문자열 → 발화 시각. 값에 시각이 있으면 그 시각, 없으면 `hour`(기본 9시) 폴백(§6-B Stage 1).
    private static func fireInstant(_ dayStr: String, calendar: Calendar, hour: Int) -> Date? {
        guard let day = ItemSchedule.parseDay(dayStr, calendar: calendar) else { return nil }
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        let hm = ItemSchedule.timeOfDay(dayStr)
        comps.hour = hm?.hour ?? hour; comps.minute = hm?.minute ?? 0
        return calendar.date(from: comps)
    }
}
