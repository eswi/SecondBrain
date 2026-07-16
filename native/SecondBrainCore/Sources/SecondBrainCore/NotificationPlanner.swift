import Foundation

/// 로컬 알림 계획 한 건.
public struct PlannedNotification: Equatable, Sendable {
    public let id: String        // 항목 id(알림 식별자로 사용)
    public let fireDate: Date    // 울릴 시각
    public let title: String
    public let body: String
}

/// push(시점 알림)의 순수 로직: 받은함 항목 → "언제 울릴지" 계획.
/// 규칙: 유효 시점 = resurface(다시 들이밀 날짜) 우선, 없으면 due. 그 날 `hour`시에 울림.
/// 과거 시점은 제외(앱 안 "곧 닥칠 것"이 담당), 미래만. 이른 순 정렬 후 limit개(iOS 64 제한 대비).
public enum NotificationPlanner {
    public static func plan(items: [ResolvedItem], now: Date,
                            calendar: Calendar = .current, hour: Int = 9, limit: Int = 32) -> [PlannedNotification] {
        var out: [PlannedNotification] = []
        for it in items {
            guard let dayStr = fireDayString(it) else { continue }
            guard let day = parseDay(dayStr, calendar: calendar) else { continue }
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

    /// resurface(날짜)면 그것, 아니면 due(날짜, none 아님). 둘 다 날짜 아니면 nil.
    private static func fireDayString(_ it: ResolvedItem) -> String? {
        if let r = it.resurface, r != "weekly", r != "none", !r.isEmpty { return r }
        if let d = it.due, d != "none", !d.isEmpty { return d }
        return nil
    }

    private static func parseDay(_ s: String, calendar: Calendar) -> Date? {
        let p = s.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }
}
