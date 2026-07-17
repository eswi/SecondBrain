import Foundation

/// D-day 버킷. 지남(빨강)/오늘(주황)/미래(무채색·D-n) 구분에 쓴다.
public enum DDayBucket: Equatable, Sendable {
    case overdue   // 지남
    case today     // 오늘
    case future    // 남음
}

/// 시점까지 남은 일수 + 버킷.
public struct DDay: Equatable, Sendable {
    public let bucket: DDayBucket
    public let days: Int    // 음수=지남, 0=오늘, 양수=남음

    public init(bucket: DDayBucket, days: Int) {
        self.bucket = bucket
        self.days = days
    }
}

public enum DDayCalc {
    /// "YYYY-MM-DD"와 기준 시각으로 D-day 계산. 날짜 경계(자정) 기준 일수. 형식 안 맞으면 nil.
    public static func compute(day: String, now: Date, calendar: Calendar = .current) -> DDay? {
        guard let target = ItemSchedule.parseDay(day, calendar: calendar) else { return nil }
        let startNow = calendar.startOfDay(for: now)
        let startTarget = calendar.startOfDay(for: target)
        let n = calendar.dateComponents([.day], from: startNow, to: startTarget).day ?? 0
        let bucket: DDayBucket = n < 0 ? .overdue : (n == 0 ? .today : .future)
        return DDay(bucket: bucket, days: n)
    }
}
