import Foundation
import SecondBrainCore

/// 받은함 상태 + 항목 행동(쓰기 경로).
/// 읽기: 사용자가 고른 iCloud 폴더의 `inbox*.md`(레거시 inbox.md 포함)를 병합.
/// 쓰기: 행동을 **이 기기 조각** `inbox-<deviceId>.md`에 이벤트로 append 후 재읽기. inbox.md는 안 건드림.
@MainActor
final class InboxModel: ObservableObject {
    // 병합 결과(삭제 아님)를 성격별로 노출
    @Published private(set) var liveNonDone: [ResolvedItem] = []   // 처리 대상(완료 제외, 원칙 포함)
    @Published private(set) var doneItems: [ResolvedItem] = []     // 보관함(완료)
    @Published private(set) var deletedCount = 0
    @Published var sourceLabel = ""
    @Published var needsFolder = false            // 폴더 미선택 → 피커 안내

    @Published var filter: TypeFilter = .all      // 받은함 필터 칩 선택

    let deviceId: String
    private var clock: HLCClock

    init() {
        let id = DeviceStore.deviceId
        self.deviceId = id
        self.clock = HLCClock(deviceId: id, last: DeviceStore.loadLastHLC(id))
    }

    // MARK: 파생 뷰

    /// 원칙(ambient) — 상단 띠 + 원칙 탭. 처리 목록에서는 뺀다.
    var principles: [ResolvedItem] { liveNonDone.filter { $0.type == "principle" } }

    /// 받은함 목록에 쓸 항목(필터 적용).
    /// - 전체: 원칙 제외(띠가 담당) — 처리할 것에 집중
    /// - 특정 종류: 그 종류만(원칙 필터면 원칙도 보임)
    var filteredInbox: [ResolvedItem] {
        switch filter {
        case .all:            return liveNonDone.filter { $0.type != "principle" }
        case .type(let key):  return liveNonDone.filter { $0.type == key }
        }
    }

    /// "곧 닥칠 것" / "최근 들어온 것" 섹션 분할(순수 로직은 Core).
    var sections: InboxSections { InboxSectionizer.split(filteredInbox, now: Date()) }

    /// 필터 칩에 배지로 쓸 종류별 개수(원칙 포함 전체 기준).
    func count(for filter: TypeFilter) -> Int {
        switch filter {
        case .all:            return liveNonDone.filter { $0.type != "principle" }.count
        case .type(let key):  return liveNonDone.filter { $0.type == key }.count
        }
    }

    // MARK: 로드

    func load() {
        guard FragmentFolder.hasFolder else {
            #if DEBUG
            if SampleData.useInSimulator {
                needsFolder = false
                resolve(EventLog.parse(SampleData.text), label: "샘플(시뮬레이터)")
                return
            }
            #endif
            needsFolder = true
            liveNonDone = []; doneItems = []; deletedCount = 0
            sourceLabel = "폴더 미선택"
            return
        }
        needsFolder = false

        let frags = FragmentFolder.readFragments()
        var events: [Event] = []
        for f in frags { events.append(contentsOf: EventLog.parse(f.text)) }
        let names = frags.map(\.name)
        resolve(events, label: names.isEmpty ? "(빈 폴더)" : names.joined(separator: ", "))
    }

    /// 이벤트 배열을 병합해 상태에 반영(시계 전진·알림 재조정 포함).
    private func resolve(_ events: [Event], label: String) {
        // 본 이벤트 최대 HLC 이상으로 시계 전진(인과성) + 영속
        if let maxH = events.map(\.hlc).max() {
            clock.receive(maxH, now: nowMillis())
            DeviceStore.saveLastHLC(clock.last)
        }

        let r = MergeEngine.merge(events)
        liveNonDone = r.live.filter { $0.status != "done" }
        doneItems = r.live.filter { $0.status == "done" }
        deletedCount = r.deleted.count
        sourceLabel = label

        scheduleNotifications()
    }

    /// 현재 살아있는 항목의 resurface/due 날짜로 로컬 알림 재조정(멱등).
    /// 파일이 진실원 → 매 로드/행동마다 계획을 다시 계산해 시스템 알림과 일치시킨다.
    private func scheduleNotifications() {
        // 실제 폴더(진실원)가 있을 때만. 샘플/시뮬레이터(폴더 없음)에선 알림 요청·스케줄 안 함.
        guard FragmentFolder.hasFolder else { return }
        let plans = NotificationPlanner.plan(items: liveNonDone, now: Date())
        Task { await NotificationScheduler.reschedule(plans) }
    }

    /// 문서 피커로 고른 폴더를 등록하고 즉시 로드.
    func setFolder(_ url: URL) {
        try? FragmentFolder.saveBookmark(for: url)
        load()
    }

    // MARK: 항목 행동 → 이벤트 append

    func delete(_ item: ResolvedItem)   { append(.delete(id: item.id, hlc: tick())) }
    func markDone(_ item: ResolvedItem) { append(.edit(id: item.id, hlc: tick(), ["status": "done"])) }
    func defer7(_ item: ResolvedItem)   { append(.edit(id: item.id, hlc: tick(), ["resurface": isoDate(daysFromNow: 7)])) }

    /// 분류(종류) 변경. 레거시(legacy: id) 항목에서도 같은 경로(=set type= 이벤트)로 동작.
    func changeType(_ item: ResolvedItem, to type: String) {
        guard type != item.type else { return }
        append(.edit(id: item.id, hlc: tick(), ["type": type]))
    }

    /// 보관함에서 되돌리기(완료 해제).
    func restore(_ item: ResolvedItem) { append(.edit(id: item.id, hlc: tick(), ["status": "open"])) }

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
