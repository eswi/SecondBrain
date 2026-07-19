import Foundation
import SecondBrainCore

/// 받은함 상태 + 항목 행동(쓰기 경로).
/// 읽기: 사용자가 고른 iCloud 폴더의 `inbox*.md`(레거시 inbox.md 포함)를 병합.
/// 쓰기: 행동을 **이 기기 조각** `inbox-<deviceId>.md`에 이벤트로 append 후 재읽기. inbox.md는 안 건드림.
@MainActor
final class InboxModel: ObservableObject {
    // 병합 결과를 성격별로 노출. 웹 분류값 discard는 '삭제'로 취급('버림' 개념 없음).
    @Published private(set) var liveNonDone: [ResolvedItem] = []   // 처리 대상(완료·삭제 제외, 원칙 포함)
    @Published private(set) var doneItems: [ResolvedItem] = []     // 보관함 완료 섹션
    @Published private(set) var trashed: [ResolvedItem] = []       // 보관함 삭제 섹션(tombstone + discard)
    @Published var sourceLabel = ""
    @Published var needsFolder = false            // 폴더 미선택 → 피커 안내

    @Published var filter: TypeFilter = .all      // 받은함 필터 칩 선택(기억 목록에만 적용)

    let deviceId: String
    private var clock: HLCClock

    /// 로드 때 파싱한 전체 이벤트(수정 이력 요약용). 엔진은 안 건드리고 여기서 경량 집계.
    private(set) var allEvents: [Event] = []

    init() {
        let id = DeviceStore.deviceId
        self.deviceId = id
        self.clock = HLCClock(deviceId: id, last: DeviceStore.loadLastHLC(id))
    }

    // MARK: 파생 뷰

    /// 원칙(ambient) — 새로운 기억 화면 상단 띠. 세 영역 분할에서는 뺀다(별도 상시 노출).
    var principles: [ResolvedItem] { liveNonDone.filter { $0.type == "principle" } }

    /// 원칙을 **순서대로**(위=고순위, memory-philosophy §3).
    /// - `order` 필드(정수) 있으면 우선(오름차순).
    /// - 없으면 그 뒤에, **포함 순서**(principle이 된 시점 = type=principle 세팅 최소 HLC)로.
    /// 엔진 무변경 — order는 일반 필드(LWW), 포함 시점은 allEvents에서 계산.
    var orderedPrinciples: [ResolvedItem] {
        principles.sorted { a, b in
            switch (orderValue(a), orderValue(b)) {
            case let (x?, y?):  return x != y ? x < y : a.id < b.id
            case (_?, nil):     return true              // 명시 순서 있는 것이 앞
            case (nil, _?):     return false
            case (nil, nil):
                let ha = inclusionHLC(a.id), hb = inclusionHLC(b.id)
                if let ha, let hb, ha != hb { return ha < hb }   // 이른 포함 = 상위
                return a.id < b.id
            }
        }
    }

    private func orderValue(_ it: ResolvedItem) -> Int? {
        guard let s = it.fields["order"] else { return nil }
        return Int(s)
    }

    /// 그 id가 principle이 된 시점(type=principle 세팅 최소 HLC). 기본 순서용.
    private func inclusionHLC(_ id: String) -> HLC? {
        allEvents.filter { $0.id == id && $0.fields["type"] == "principle" }.map(\.hlc).min()
    }

    var deletedCount: Int { trashed.count }

    /// 전체 항목 회계(고유 id 합). 합계가 원본(예: inbox.md 68)과 같아야 파싱 누락이 없다.
    /// live(완료·버림 제외) + 완료 + 삭제·버림 = 전체.
    var totalCount: Int { liveNonDone.count + doneItems.count + trashed.count }

    /// 빈 문자열 type은 미분류(nil)로 취급.
    private func norm(_ t: String?) -> String? { (t?.isEmpty ?? true) ? nil : t }

    // MARK: 세 영역 분할 (memory-philosophy.md §5)

    /// **시점(Due/Resurface) 유무가 최상위 축.** 배타적·중복 없음:
    /// - 시점 있음 → **지금 챙길 것** (확정 무관 — 현실의 사건은 완료되면 보관으로 흐름)
    /// - 시점 없음 + 미확정 → **새 기억들** (오래된 순 = 선입선출, 묻히지 않게)
    /// - 시점 없음 + 확정 → **살아있는 기억** (시점 없는 것만이 살아있는 기억의 몫)
    /// 원칙(principle)은 어디에도 안 들어가고 별도 ambient 띠(`principles`).
    struct Partition {
        var upcoming: [UpcomingEntry]
        var newMemories: [ResolvedItem]   // 시점 없음 + 미확정, 오래된 순
        var living: [ResolvedItem]         // 시점 없음 + 확정 (필터 전)
    }

    private var partition: Partition {
        let nonPrinciple = liveNonDone.filter { $0.type != "principle" }
        let base = InboxSectionizer.split(nonPrinciple, now: Date())
        let newMems = base.recent
            .filter { !$0.confirmed }
            .sorted { a, b in a.createdHLC != b.createdHLC ? a.createdHLC < b.createdHLC : a.id < b.id }
        let living = base.recent.filter { $0.confirmed }   // recent는 MergeEngine 최신순 유지
        return Partition(upcoming: base.upcoming, newMemories: newMems, living: living)
    }

    /// 새로운 기억 탭: 지금 챙길 것 + 새 기억들. (필터 미적용 — 필터는 살아있는 기억 탭 몫)
    var newTab: (upcoming: [UpcomingEntry], newMemories: [ResolvedItem]) {
        let p = partition; return (p.upcoming, p.newMemories)
    }

    /// 살아있는 기억 탭: 시점 없는 확정 항목(+ 필터 적용).
    var livingMemories: [ResolvedItem] {
        let all = partition.living
        switch filter {
        case .all:            return all
        case .type(let key):  return all.filter { norm($0.type) == key }
        }
    }

    // 대시보드 5숫자
    var principleCount: Int { principles.count }               // 원칙(ambient 띠) 개수
    var upcomingCount: Int { partition.upcoming.count }        // 챙길 것 = 지금 챙길 것 섹션과 동일
    var unconfirmedCount: Int { partition.newMemories.count }   // 미확정(시점 없는)
    var confirmedCount: Int { partition.living.count }          // 확정(시점 없는)
    var totalMemoryCount: Int { liveNonDone.count }             // 총 기억 = 현재 살아있는 전체(원칙·챙길것·미확정·확정)

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
            liveNonDone = []; doneItems = []; trashed = []
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
        allEvents = events   // 이력 요약용 원본 보관
        // 본 이벤트 최대 HLC 이상으로 시계 전진(인과성) + 영속
        if let maxH = events.map(\.hlc).max() {
            clock.receive(maxH, now: nowMillis())
            DeviceStore.saveLastHLC(clock.last)
        }

        let r = MergeEngine.merge(events)
        // 웹 분류값 discard는 삭제로 취급: 받은함·완료에서 빼고 trashed로('버림' 개념 없음).
        let active = r.live.filter { $0.type != "discard" }
        liveNonDone = active.filter { $0.status != "done" }
        doneItems = active.filter { $0.status == "done" }
        trashed = r.deleted + r.live.filter { $0.type == "discard" }
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
    /// **override는 확정이 아니다**(edit-policy §2 귀결) — 여긴 confirm을 안 건다.
    func changeType(_ item: ResolvedItem, to type: String) {
        guard type != item.type else { return }
        append(.edit(id: item.id, hlc: tick(), ["type": type]))
    }

    /// 상세 화면 draft 커밋(edit-policy §2 [저장]). 바뀐 필드를 **이벤트 1개**(단일 HLC)로 붙인다
    /// → "[저장] 한 번 = 이력 한 묶음". `changes`엔 confirmed가 없다(수정 ≠ 기억하기) — EditDiff가 보장.
    func commitEdits(_ item: ResolvedItem, changes: [String: String]) {
        guard !changes.isEmpty else { return }
        append(.edit(id: item.id, hlc: tick(), changes))
    }

    /// 앱 안 수집 — **네이티브 항목(UUID) 생성**. 최초 수집 정보(시각·기기·source)를
    /// create 이벤트에 **성역으로 찍는다**(이후 어떤 편집도 안 건드림). 자동 분류는 다음 단계 → 미분류로 시작.
    /// v1은 원문 한 줄 유지를 위해 줄바꿈을 공백으로 접는다(여러 줄 보존은 나중).
    func capture(text: String, source: String) {
        let raw = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let now = Date()
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; let date = f.string(from: now)
        f.dateFormat = "HH:mm";     let time = f.string(from: now)
        let e = Event.create(id: UUID().uuidString, hlc: tick(),
                             date: date, time: time, source: source, raw: raw,
                             extra: ["device": CaptureDevice.currentLabel()])
        append(e)
    }

    /// 확정: 사람이 항목을 최종으로 승격(edit-policy §1~3). **단방향** — 되돌리는 API는 없다.
    /// 이미 확정된 항목엔 중복 이벤트를 안 쌓는다(멱등).
    func confirm(_ item: ResolvedItem) {
        guard !item.confirmed else { return }
        append(.confirm(id: item.id, hlc: tick()))
    }

    /// 수정 이력 요약(경량, edit-policy §4-4의 최소형). 엔진 무변경 — 로드 때 보관한 이벤트를
    /// id로 묶어 개수만 센다. create(최소 HLC) 1개를 뺀 나머지가 "수정 횟수".
    /// last = 그 id 이벤트 중 최대 벽시계(밀리). 레거시(wall=0)뿐이면 nil.
    func historySummary(_ id: String) -> (edits: Int, lastMillis: Int64?) {
        let evs = allEvents.filter { $0.id == id }
        guard !evs.isEmpty else { return (0, nil) }
        let edits = max(0, evs.count - 1)
        let last = evs.map { $0.hlc.wallMillis }.max() ?? 0
        return (edits, last > 0 ? last : nil)
    }

    /// 보관함 완료 섹션에서 되돌리기(완료 해제).
    func restore(_ item: ResolvedItem) { append(.edit(id: item.id, hlc: tick(), ["status": "open"])) }

    /// 보관함 삭제 섹션에서 되돌리기.
    /// - 진짜 삭제(tombstone) → undelete로 부활.
    /// - discard(삭제 취급) → type을 비워 미분류로(받은함에 다시 나타남).
    func restoreFromTrash(_ item: ResolvedItem) {
        if item.deleted { append(.undelete(id: item.id, hlc: tick())) }
        else { append(.edit(id: item.id, hlc: tick(), ["type": ""])) }
    }

    private func tick() -> HLC {
        let h = clock.send(now: nowMillis())
        DeviceStore.saveLastHLC(clock.last)
        return h
    }

    private func append(_ e: Event) {
        try? FragmentFolder.appendLine(EventWriter.serialize(e) + "\n", deviceId: deviceId)
        load()   // 파일이 진실원 → 재읽기·재병합
    }

    /// 여러 이벤트를 한 번에 append 후 **한 번만** 재로드(순서 재부여용 — N개 항목 재기록).
    private func appendBatch(_ events: [Event]) {
        guard !events.isEmpty else { return }
        for e in events {
            try? FragmentFolder.appendLine(EventWriter.serialize(e) + "\n", deviceId: deviceId)
        }
        load()
    }

    /// 원칙 목록 드래그 순서 변경 → 새 순서대로 `order` 재부여(0..n-1). 바뀐 항목만 기록.
    func reorderPrinciples(_ ordered: [ResolvedItem]) {
        var events: [Event] = []
        for (i, it) in ordered.enumerated() where orderValue(it) != i {
            events.append(.edit(id: it.id, hlc: tick(), ["order": String(i)]))
        }
        appendBatch(events)
    }

    private func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func isoDate(daysFromNow d: Int) -> String {
        let dt = Calendar.current.date(byAdding: .day, value: d, to: Date()) ?? Date()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: dt)
    }
}
