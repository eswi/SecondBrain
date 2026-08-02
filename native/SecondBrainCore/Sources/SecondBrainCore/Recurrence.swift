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
        if it.type == "recurrence" {
            return [lastDoneKey: ItemSchedule.dayTimeString(now, calendar: calendar)]
        }
        return ["status": "done"]
    }

    /// **완료 취소용 — 직전 완료 시점.** 이벤트 이력에서 lastDone 값들 중 **두 번째 최신**(=방금 것 이전).
    /// 되돌리면 놓침 계산의 streak가 보존된다(오늘 것만 무르고 어제까지는 남김). 없으면 nil(→ 비움).
    public static func priorLastDone(in events: [Event], id: String) -> String? {
        let vals = events
            .filter { $0.id == id && $0.fields[lastDoneKey] != nil }
            .sorted { $0.hlc < $1.hlc }
            .map { $0.fields[lastDoneKey]! }
        guard vals.count >= 2 else { return nil }
        let prior = vals[vals.count - 2]
        return prior.isEmpty ? nil : prior
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
