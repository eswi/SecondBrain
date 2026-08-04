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
/// 과거 시점은 제외(앱 안 '지금 챙길 것'이 담당), 미래만. 이른 순 정렬 후 limit개(iOS 64 제한 대비).
/// 정렬은 (시각, id, 종류)로 **완전 결정적** — 상한에 걸릴 때 무엇이 남는지가 흔들리지 않게.
///
/// **문구는 아직 한 종류다** — 곧/지금/오늘 세 톤으로 가르는 것은 Stage 5-D. 여기선 지점만 갈랐다.
/// **예산 분리(반복/일반)와 체인(며칠 치)은 5-B·5-C** — 지금은 상한 32 그대로라 iOS 64에 안 닿는다.
public enum NotificationPlanner {
    public static func plan(items: [ResolvedItem], now: Date,
                            calendar: Calendar = .current, hour: Int = 9, limit: Int = 32) -> [PlannedNotification] {
        var out: [PlannedNotification] = []
        for it in items {
            if Recurrence.isDormant(it) { continue }   // 꺼둔 되풀이는 알림 안 냄(배너 약속, 2026-08-03)

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

            for p in points where p.fire > now {   // 미래만
                out.append(PlannedNotification(
                    id: it.id, kind: p.kind, fireDate: p.fire,
                    title: "받은함 · 곧 닥칠 것",   // 5-D에서 곧/지금/오늘로 갈린다
                    body: it.raw ?? "(항목)"))
            }
        }
        return Array(out.sorted { a, b in
            if a.fireDate != b.fireDate { return a.fireDate < b.fireDate }
            if a.id != b.id { return a.id < b.id }
            return a.kind.order < b.kind.order
        }.prefix(limit))
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
