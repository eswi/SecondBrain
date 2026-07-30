import Foundation

/// "곧 닥칠 것" 한 항목 — 시점 항목 + 정렬·표시 기준일 + (마감 있으면) 디데이.
public struct UpcomingEntry: Sendable, Equatable {
    public let item: ResolvedItem
    /// 정렬·표시 기준일 = `deadlineDay`(마감) 있으면 그것, 없으면 `publishDay`(게시 시작).
    public let day: String
    /// D-day 배지 = **마감(deadlineDay) 기준**. 마감이 없으면(미리 알림만 있는 항목) `nil` → 배지 없음.
    public let dday: DDay?
    public init(item: ResolvedItem, day: String, dday: DDay?) {
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
    /// - **멤버십**: `publishDay`(게시 시작일)가 있으면 곧 닥칠 것. (게시 게이트는 Stage 2에서 얹는다.)
    /// - **정렬**: `deadlineDay`(마감) 우선, 없으면 `publishDay`로 D-day 오름차순(지남 → 오늘 → 임박) + id tiebreak.
    /// - **배지**: `deadlineDay` 기준. 마감 없는 항목(미리 알림만)은 `dday=nil` → 배지 안 뜬다.
    /// recent는 입력 순서 유지(MergeEngine이 이미 캡처 최신순으로 정렬해 줌).
    public static func split(_ items: [ResolvedItem], now: Date, calendar: Calendar = .current) -> InboxSections {
        var scored: [(entry: UpcomingEntry, order: Int)] = []
        var recent: [ResolvedItem] = []
        for it in items {
            guard let pub = ItemSchedule.publishDay(it) else { recent.append(it); continue }
            let deadline = ItemSchedule.deadlineDay(it)
            let sortDay = deadline ?? pub
            guard let order = DDayCalc.compute(day: sortDay, now: now, calendar: calendar) else {
                recent.append(it); continue   // 방어: 기준일이 파싱 안 되면 시점 없음 취급(유실 방지)
            }
            let badge = deadline.flatMap { DDayCalc.compute(day: $0, now: now, calendar: calendar) }
            scored.append((UpcomingEntry(item: it, day: sortDay, dday: badge), order.days))
        }
        scored.sort { a, b in
            if a.order != b.order { return a.order < b.order }
            return a.entry.item.id < b.entry.item.id
        }
        return InboxSections(upcoming: scored.map(\.entry), recent: recent)
    }
}
