import Foundation

/// 받은함 한 항목. 조각 파일(설계서 §0-A: `inbox-iphone.md` 등)의 한 블록.
/// 줄 형식(§1): `- YYYY-MM-DD HH:MM | source | 원문` + 들여쓴 `key: value` 필드들.
/// 원문(raw)은 절대 변형하지 않는다 — 분류/상태는 필드로만 덧붙는다.
public struct InboxItem: Equatable, Sendable {
    public var date: String        // "2026-07-15"
    public var time: String        // "10:51"
    public var source: String      // voice / web / image / mail / doc / chat / meeting
    public var raw: String         // 수집된 원문 그대로

    public var type: String?       // event/promise/info-action/info/idea/principle/discard (§2)
    public var due: String?        // "YYYY-MM-DD" | "none" | nil
    public var resurface: String?  // "YYYY-MM-DD" | "weekly" | nil
    public var status: String?     // open / done / ...
    public var question: String?   // info-action 재확인 질문(§3) — 있으면
    public var notes: [String]     // 그 외 들여쓴 줄(여러 줄 원문/메모)

    /// 이 항목이 어느 조각 파일에서 왔는지(합치기·출처 추적용). 파서가 채운다.
    public var sourceFile: String?

    public init(date: String, time: String, source: String, raw: String,
                type: String? = nil, due: String? = nil, resurface: String? = nil,
                status: String? = nil, question: String? = nil,
                notes: [String] = [], sourceFile: String? = nil) {
        self.date = date; self.time = time; self.source = source; self.raw = raw
        self.type = type; self.due = due; self.resurface = resurface
        self.status = status; self.question = question
        self.notes = notes; self.sourceFile = sourceFile
    }

    /// 안정적 식별자(합치기 중복제거·로컬 상태 키). 헤더(날짜·시각·source·원문) 기반.
    public var id: String { "\(date) \(time)|\(source)|\(raw)" }
}
