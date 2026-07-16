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
        return Event(id: "legacy:" + item.id,
                     hlc: HLC(wallMillis: 0, counter: index, deviceId: "legacy"),
                     fields: f)
    }
}
