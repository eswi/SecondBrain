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
