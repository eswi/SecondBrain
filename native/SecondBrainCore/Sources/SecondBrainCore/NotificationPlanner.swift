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

    public init(id: String, kind: Kind, fireDate: Date, title: String, body: String) {
        self.id = id; self.kind = kind; self.fireDate = fireDate; self.title = title; self.body = body
    }

    /// 시스템 알림 식별자의 항목 부분(접두어 `sb:`는 앱이 붙인다).
    /// **한 항목이 두 건을 내므로 종류까지 넣어야 한다** — 안 갈면 두 번째 등록이 첫 번째를 덮어쓴다.
    public var requestKey: String { "\(id):\(kind.rawValue)" }
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

    public var droppedCycles: Int { droppedRecurringCycles + droppedPlainCycles }
    public var used: Int { usedRecurring + usedPlain }

    /// 사람이 읽는 한 줄 — 로그·디버그 화면 공용. **확인 경로**가 이걸로 하나로 모인다.
    public var summary: String {
        var s = "알림 \(used)건(반복 \(usedRecurring)/일반 \(usedPlain))"
        if borrowedFromPlain > 0 { s += " · 대여 \(borrowedFromPlain)" }
        if droppedCycles > 0 {
            s += " · ⚠️잘림 \(droppedCycles)회차(\(droppedSlots)건: 반복 \(droppedRecurringCycles)/일반 \(droppedPlainCycles))"
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
/// **문구는 아직 한 종류다** — 곧/지금/오늘 세 톤으로 가르는 것은 Stage 5-D. 여기선 지점만 갈랐다.
/// **체인(며칠 치 미리)은 5-C** — 지금은 항목당 **현재 회차 하나**만 낸다.
public enum NotificationPlanner {
    /// 편의 — 계획된 알림만. 회계까지 필요하면 `planned(...)`.
    public static func plan(items: [ResolvedItem], now: Date,
                            calendar: Calendar = .current, hour: Int = 9,
                            budget: NotificationBudget = .standard) -> [PlannedNotification] {
        planned(items: items, now: now, calendar: calendar, hour: hour, budget: budget).scheduled
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
                               budget: NotificationBudget = .standard) -> NotificationPlanResult {
        var recurringQueues: [[Bundle]] = []
        var plainQueues: [[Bundle]] = []
        for it in items {
            if Recurrence.isDormant(it) { continue }   // 꺼둔 되풀이는 알림 안 냄(배너 약속, 2026-08-03)
            guard let b = cycleBundle(it, now: now, calendar: calendar, hour: hour) else { continue }
            if b.isRecurring { recurringQueues.append([b]) } else { plainQueues.append([b]) }
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
            droppedSlots: (recurFill.dropped + plainFill.dropped).reduce(0) { $0 + $1.slots })
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
    private static func roundRobin(_ queues: [[Bundle]], budget: Int)
        -> (placed: [Bundle], dropped: [Bundle], used: Int) {
        var placed: [Bundle] = [], dropped: [Bundle] = [], used = 0
        let maxRound = queues.map(\.count).max() ?? 0
        for round in 0..<maxRound {
            let ordered = queues.compactMap { round < $0.count ? $0[round] : nil }
                .sorted { $0.earliest != $1.earliest ? $0.earliest < $1.earliest : $0.itemId < $1.itemId }
            for b in ordered {
                if used + b.slots <= budget { placed.append(b); used += b.slots } else { dropped.append(b) }
            }
        }
        return (placed, dropped, used)
    }

    /// 항목의 현재 회차 묶음(미래 지점만). 낼 게 없으면 nil.
    private static func cycleBundle(_ it: ResolvedItem, now: Date,
                                   calendar: Calendar, hour: Int) -> Bundle? {
        let leadFire = ItemSchedule.gatedResurface(it).flatMap { fireInstant($0, calendar: calendar, hour: hour) }
        let dueFire  = ItemSchedule.deadlineDay(it).flatMap  { fireInstant($0, calendar: calendar, hour: hour) }

        var points: [(kind: PlannedNotification.Kind, fire: Date)] = []
        if let d = dueFire { points.append((.due, d)) }
        // lead 0 접힘 — 마감과 같은 시각이면 안 넣는다. 마감이 없으면(nil) lead만 남는다.
        if let l = leadFire, l != dueFire { points.append((.lead, l)) }

        if notifyOnly(it), points.count > 1 {
            // 알려주는 알림은 한 건만 — lead 우선(미리 알아야 쓸모가 있다).
            points = points.filter { $0.kind == .lead }
        }

        let planned = points.filter { $0.fire > now }.map {   // 미래만
            PlannedNotification(id: it.id, kind: $0.kind, fireDate: $0.fire,
                                title: "받은함 · 곧 닥칠 것",   // 5-D에서 곧/지금/오늘로 갈린다
                                body: it.raw ?? "(항목)")
        }
        guard !planned.isEmpty else { return nil }
        return Bundle(itemId: it.id, isRecurring: it.type == "recurrence", points: planned)
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
