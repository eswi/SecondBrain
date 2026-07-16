import Foundation
import SecondBrainCore

/// 받은함 상태 + 항목 행동(쓰기 경로). 행동은 이 기기 조각 파일에 이벤트로 append 후 재읽기.
@MainActor
final class InboxModel: ObservableObject {
    @Published var visible: [ResolvedItem] = []   // 화면에 보일 것(삭제·완료 제외)
    @Published var deletedCount = 0
    @Published var doneCount = 0
    @Published var sourceLabel = ""

    let deviceId: String
    private var clock: HLCClock

    init() {
        let id = DeviceStore.deviceId
        self.deviceId = id
        self.clock = HLCClock(deviceId: id, last: DeviceStore.loadLastHLC(id))
    }

    func load() {
        let docs = DeviceStore.documents()
        var (events, names) = InboxStore.eventsInDirectory(docs)

        if events.isEmpty {   // 실 조각 없으면 번들 데모(2기기)
            for n in ["inbox-iphone", "inbox-mac"] {
                if let u = Bundle.main.url(forResource: n, withExtension: "md"),
                   let t = try? String(contentsOf: u, encoding: .utf8) {
                    events.append(contentsOf: EventLog.parse(t))
                    names.append("\(n).md(번들)")
                }
            }
        }

        // 본 이벤트 최대 HLC 이상으로 시계 전진(인과성) + 영속
        if let maxH = events.map(\.hlc).max() {
            clock.receive(maxH, now: nowMillis())
            DeviceStore.saveLastHLC(clock.last)
        }

        let r = MergeEngine.merge(events)
        visible = r.live.filter { $0.status != "done" }
        doneCount = r.live.count - visible.count
        deletedCount = r.deleted.count
        sourceLabel = names.isEmpty ? "(빈 받은함)" : names.joined(separator: ", ")
    }

    // ---- 항목 행동 → 이벤트 append ----

    func delete(_ item: ResolvedItem)   { append(.delete(id: item.id, hlc: tick())) }
    func markDone(_ item: ResolvedItem) { append(.edit(id: item.id, hlc: tick(), ["status": "done"])) }
    func defer7(_ item: ResolvedItem)   { append(.edit(id: item.id, hlc: tick(), ["resurface": isoDate(daysFromNow: 7)])) }

    private func tick() -> HLC {
        let h = clock.send(now: nowMillis())
        DeviceStore.saveLastHLC(clock.last)
        return h
    }

    private func append(_ e: Event) {
        try? EventWriter.append(e, to: DeviceStore.fragmentURL(deviceId))
        load()   // 파일이 진실원 → 재읽기·재병합
    }

    private func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func isoDate(daysFromNow d: Int) -> String {
        let dt = Calendar.current.date(byAdding: .day, value: d, to: Date()) ?? Date()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: dt)
    }
}
