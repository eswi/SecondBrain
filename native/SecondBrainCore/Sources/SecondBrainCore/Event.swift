import Foundation

/// 이벤트 소싱의 단위. 한 항목(`id`)에 대한 한 번의 행동.
/// `fields`는 이 이벤트가 세팅하는 키/값. 제어 필드 `deleted`("true"/"false")로 삭제/부활 표현.
public struct Event: Sendable, Equatable {
    public let id: String
    public let hlc: HLC
    public let fields: [String: String]

    public init(id: String, hlc: HLC, fields: [String: String]) {
        self.id = id
        self.hlc = hlc
        self.fields = fields
    }

    // ---- 팩토리 (읽기 쉬운 이벤트 생성) ----

    /// 최초 캡처. 헤더(date/time/source/raw)와 초기 분류 필드를 세팅.
    public static func create(id: String, hlc: HLC,
                              date: String, time: String, source: String, raw: String,
                              extra: [String: String] = [:]) -> Event {
        var f = extra
        f["date"] = date; f["time"] = time; f["source"] = source; f["raw"] = raw
        return Event(id: id, hlc: hlc, fields: f)
    }

    /// 필드 수정(분류·시점 등). 미루기(defer)=resurface 세팅, 완료(done)=status 세팅도 이걸로.
    public static func edit(id: String, hlc: HLC, _ fields: [String: String]) -> Event {
        Event(id: id, hlc: hlc, fields: fields)
    }

    public static func delete(id: String, hlc: HLC) -> Event {
        Event(id: id, hlc: hlc, fields: ["deleted": "true"])
    }

    /// 확정: 사람이 항목을 "최종"으로 승격(edit-policy.md §1~3).
    /// **단방향** — 되돌리는 unconfirm 팩토리는 의도적으로 없다. 병합도 OR-머지라
    /// 한 번 확정된 항목은 이후 어떤 편집·HLC로도 미확정으로 돌아가지 않는다.
    public static func confirm(id: String, hlc: HLC) -> Event {
        Event(id: id, hlc: hlc, fields: ["confirmed": "true"])
    }

    public static func undelete(id: String, hlc: HLC) -> Event {
        Event(id: id, hlc: hlc, fields: ["deleted": "false"])
    }

    /// 레거시 v0 항목(FragmentParser 산출)을 최하 우선순위 create 이벤트로 편입(설계 §1).
    public static func fromLegacy(_ item: InboxItem, index: Int) -> Event {
        var f: [String: String] = ["date": item.date, "time": item.time,
                                    "source": item.source, "raw": item.raw]
        if let t = item.type { f["type"] = t }
        if let d = item.due { f["due"] = d }
        if let r = item.resurface { f["resurface"] = r }
        if let s = item.status { f["status"] = s }
        return Event(id: legacyID(date: item.date, time: item.time, source: item.source, raw: item.raw),
                     hlc: HLC(wallMillis: 0, counter: index, deviceId: "legacy"),
                     fields: f)
    }

    /// 레거시 v0 줄(id 없음)에 부여하는 **토큰 안전 안정 id**: `legacy:<16hex>`.
    /// - 내용(date/time/source/raw) 기반 결정적 해시(FNV-1a 64bit) → 같은 원문이면 항상 같은 id.
    ///   classify.py가 원문 헤더 줄을 보존하므로 재분류해도 불변(원문을 손으로 고칠 때만 바뀜).
    /// - `@ hlc | id | verb` 변이 줄에서 쪼개지지 않도록 '|'·공백 없는 16진 토큰만 만든다.
    ///   (v0의 "date time|source|raw" 원문 id를 그대로 쓰면 변이 이벤트가 파싱 시 깨짐 — 그래서 해시.)
    public static func legacyID(date: String, time: String, source: String, raw: String) -> String {
        let s = "\(date) \(time)|\(source)|\(raw)"
        var h: UInt64 = 0xcbf29ce484222325                  // FNV-1a offset basis
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        let hex = String(h, radix: 16)
        return "legacy:" + String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}
