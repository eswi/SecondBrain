import Foundation

/// 로컬 알림 계획 한 건.
public struct PlannedNotification: Equatable, Sendable {
    public let id: String        // 항목 id(알림 식별자로 사용)
    public let fireDate: Date    // 울릴 시각
    public let title: String
    public let body: String
}

/// push(시점 알림)의 순수 로직: 받은함 항목 → "언제 울릴지" 계획.
/// 규칙: 알림은 **게시 시작일**(`publishDay` = 미리 알림 우선, 없으면 마감)에 울린다 — 미리 알림의 의미
/// 자체가 "이날부터 챙겨"이므로 게시 시작이 알림 시점이다. 그 날 `hour`시에 울림.
/// (마감일 별도 알림은 이번 범위 아님 — 게시 시작 알림만.)
/// 과거 시점은 제외(앱 안 "곧 닥칠 것"이 담당), 미래만. 이른 순 정렬 후 limit개(iOS 64 제한 대비).
public enum NotificationPlanner {
    public static func plan(items: [ResolvedItem], now: Date,
                            calendar: Calendar = .current, hour: Int = 9, limit: Int = 32) -> [PlannedNotification] {
        var out: [PlannedNotification] = []
        for it in items {
            guard let dayStr = ItemSchedule.publishDay(it) else { continue }
            guard let day = ItemSchedule.parseDay(dayStr, calendar: calendar) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour; comps.minute = 0
            guard let fire = calendar.date(from: comps), fire > now else { continue }  // 미래만
            out.append(PlannedNotification(
                id: it.id, fireDate: fire,
                title: "받은함 · 곧 닥칠 것",
                body: it.raw ?? "(항목)"))
        }
        return Array(out.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }
}
