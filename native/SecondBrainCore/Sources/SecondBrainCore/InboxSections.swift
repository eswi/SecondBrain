import Foundation

/// "곧 닥칠 것" 한 항목 — 시점 항목 + 그 날짜/디데이.
public struct UpcomingEntry: Sendable, Equatable {
    public let item: ResolvedItem
    public let day: String
    public let dday: DDay
    public init(item: ResolvedItem, day: String, dday: DDay) {
        self.item = item; self.day = day; self.dday = dday
    }
}

/// 받은함 섹션 분할 결과.
public struct InboxSections: Sendable, Equatable {
    public let upcoming: [UpcomingEntry]   // 시점 있음 — 임박 순(지남 먼저)
    public let recent: [ResolvedItem]      // 시점 없음 — 입력 순서(=캡처 최신순) 유지
    public init(upcoming: [UpcomingEntry], recent: [ResolvedItem]) {
        self.upcoming = upcoming; self.recent = recent
    }
}

public enum InboxSectionizer {
    /// 항목을 "곧 닥칠 것"(시점 있음)과 "최근 들어온 것"(시점 없음)으로 나눈다.
    /// upcoming은 D-day 오름차순(지남 → 오늘 → 임박) + id tiebreak로 결정적 정렬.
    /// recent는 입력 순서 유지(MergeEngine이 이미 캡처 최신순으로 정렬해 줌).
    public static func split(_ items: [ResolvedItem], now: Date, calendar: Calendar = .current) -> InboxSections {
        var upcoming: [UpcomingEntry] = []
        var recent: [ResolvedItem] = []
        for it in items {
            if let day = ItemSchedule.effectiveDay(it),
               let dd = DDayCalc.compute(day: day, now: now, calendar: calendar) {
                upcoming.append(UpcomingEntry(item: it, day: day, dday: dd))
            } else {
                recent.append(it)
            }
        }
        upcoming.sort { a, b in
            if a.dday.days != b.dday.days { return a.dday.days < b.dday.days }
            return a.item.id < b.item.id
        }
        return InboxSections(upcoming: upcoming, recent: recent)
    }
}
