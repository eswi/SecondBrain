import Foundation
import SecondBrainCore

/// 받은함 상태 + 항목 행동(쓰기 경로).
/// 읽기: 사용자가 고른 iCloud 폴더의 `inbox*.md`(레거시 inbox.md 포함)를 병합.
/// 쓰기: 행동을 **이 기기 조각** `inbox-<deviceId>.md`에 이벤트로 append 후 재읽기. inbox.md는 안 건드림.
@MainActor
final class InboxModel: ObservableObject {
    @Published var visible: [ResolvedItem] = []   // 화면에 보일 것(삭제·완료 제외)
    @Published var deletedCount = 0
    @Published var doneCount = 0
    @Published var sourceLabel = ""
    @Published var needsFolder = false            // 폴더 미선택 → 피커 안내

    let deviceId: String
    private var clock: HLCClock

    init() {
        let id = DeviceStore.deviceId
        self.deviceId = id
        self.clock = HLCClock(deviceId: id, last: DeviceStore.loadLastHLC(id))
    }

    func load() {
        guard FragmentFolder.hasFolder else {
            needsFolder = true
            visible = []; deletedCount = 0; doneCount = 0
            sourceLabel = "폴더 미선택"
            return
        }
        needsFolder = false

        let frags = FragmentFolder.readFragments()
        var events: [Event] = []
        for f in frags { events.append(contentsOf: EventLog.parse(f.text)) }

        // 본 이벤트 최대 HLC 이상으로 시계 전진(인과성) + 영속
        if let maxH = events.map(\.hlc).max() {
            clock.receive(maxH, now: nowMillis())
            DeviceStore.saveLastHLC(clock.last)
        }

        let r = MergeEngine.merge(events)
        visible = r.live.filter { $0.status != "done" }
        doneCount = r.live.count - visible.count
        deletedCount = r.deleted.count
        let names = frags.map(\.name)
        sourceLabel = names.isEmpty ? "(빈 폴더)" : names.joined(separator: ", ")
    }

    /// 문서 피커로 고른 폴더를 등록하고 즉시 로드.
    func setFolder(_ url: URL) {
        try? FragmentFolder.saveBookmark(for: url)
        load()
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
        try? FragmentFolder.appendLine(EventWriter.serialize(e) + "\n", deviceId: deviceId)
        load()   // 파일이 진실원 → 재읽기·재병합
    }

    private func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func isoDate(daysFromNow d: Int) -> String {
        let dt = Calendar.current.date(byAdding: .day, value: d, to: Date()) ?? Date()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: dt)
    }
}
