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

    /// 리스트(스와이프·컨텍스트) 삭제 재확인 대기 항목. nil이 아니면 RootView가 공용 확인 팝업을 띄운다.
    /// (상세 화면 [삭제하기]는 자체 확인 후 dismiss하므로 이 경로를 안 쓴다.)
    @Published var pendingDelete: ResolvedItem?

    /// 자동 분류 진행 상태(설정의 수동 버튼에서 그 자리 인라인 표시).
    enum ClassifyPhase: Equatable { case idle, running, done(Int), failed(String) }
    @Published var classifyPhase: ClassifyPhase = .idle

    /// **앱 열 때 자동 스윕** 전용 토스트 — 머물던 화면 위 상단에 띄운다(설정으로 안 끌고 감).
    /// 수동 버튼(설정)은 이걸 안 쓰고 classifyPhase만 쓴다.
    struct ClassifyToast: Equatable {
        enum Kind { case running, success, failure }
        let kind: Kind
        let text: String
    }
    @Published var autoToast: ClassifyToast?

    let deviceId: String
    private var clock: HLCClock
    private var loadGen = 0        // 비동기 로드 세대 — 늦게 끝난 낡은 로드 결과를 버리기 위한 가드

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

    /// 미분류(type 없음) 살아있는 항목 = 자동 분류 대상(수집됐지만 아직 분류 안 됨).
    var unclassifiedItems: [ResolvedItem] { liveNonDone.filter { norm($0.type) == nil } }

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

    /// 살아있는 기억 필터 칩에 노출할 분류 = **실제 존재하는 것만**(필터 전 `partition.living` 기준).
    /// 순서·라벨은 `FilterChipsBar`가 `ClassRegistry`로 정리 — 여기선 distinct 집합만.
    var livingPresentTypes: [String?] {
        Array(Set(partition.living.map { norm($0.type) }))
    }

    // 대시보드 5숫자
    var principleCount: Int { principles.count }               // 원칙(ambient 띠) 개수
    var upcomingCount: Int { partition.upcoming.count }        // 챙길 것 = 지금 챙길 것 섹션과 동일
    var unconfirmedCount: Int { partition.newMemories.count }   // 미확정(시점 없는)
    var confirmedCount: Int { partition.living.count }          // 확정(시점 없는)
    var totalMemoryCount: Int { liveNonDone.count }             // 총 기억 = 현재 살아있는 전체(원칙·챙길것·미확정·확정)

    // MARK: 로드

    /// 파일에서 다시 읽어 상태 반영(fire-and-forget). append·행동 경로에서 호출.
    func load() { Task { await reload() } }

    /// 로드 본체(await 가능 — 초기 로드 뒤 자동분류를 잇기 위해 뷰가 기다릴 수 있게).
    /// **파일 I/O(iCloud 조율 읽기)는 백그라운드**에서 돈다 — 메인 스레드를 막지 않는다.
    /// (콜드 iCloud에서 동기 조율 읽기가 수십 초 앱을 얼리던 문제 수정.) 결과 반영만 메인.
    func reload() async {
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
        loadGen &+= 1
        let gen = loadGen
        let (events, label) = await Self.readAndParse()
        guard gen == loadGen else { return }   // 그사이 더 최신 로드가 시작됨 → 낡은 결과 버림
        resolve(events, label: label)
    }

    /// 폴더의 조각을 읽고 파싱 — 전부 **메인 밖**(Task.detached). 순수 값(Event: Sendable)만 돌려준다.
    private static func readAndParse() async -> ([Event], String) {
        await Task.detached(priority: .userInitiated) {
            let frags = FragmentFolder.readFragments()
            var events: [Event] = []
            for f in frags { events.append(contentsOf: EventLog.parse(f.text)) }
            let label = frags.isEmpty ? "(빈 폴더)" : frags.map(\.name).joined(separator: ", ")
            return (events, label)
        }.value
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

    /// 앱 안 수집 — **네이티브 항목(UUID) 생성**. 최초 수집 정보(시각·기기·source·음성)를
    /// create 이벤트에 **성역으로 찍는다**(이후 어떤 편집도 안 건드림). 자동 분류는 다음 단계 → 미분류로 시작.
    /// v1은 원문 한 줄 유지를 위해 줄바꿈을 공백으로 접는다(여러 줄 보존은 나중).
    /// - Parameter audioTemp: 캡처 중 녹음된 임시 음성 파일. 있으면 항목 UUID로 확정(`<uuid>.m4a`, 불변)하고
    ///   `audio:` 포인터를 성역에 찍는다. 확정 실패·없음이면 음성 없이 생성(graceful).
    /// - Parameter photoTemp: 촬영된 임시 사진 파일(리사이즈·압축본). 있으면 `<uuid>.jpg`로 확정하고
    ///   `photo:` 포인터를 성역에 찍는다(audio와 동형·불변). 확정 실패·없음이면 사진 없이 생성(graceful).
    ///   **원문 없는 기억은 만들지 않는다** — raw 비면 audio·photo 임시를 지우고 항목을 안 만든다(마지막 백스톱).
    func capture(text: String, source: String, audioTemp: URL? = nil, photoTemp: URL? = nil) {
        let raw = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            if let audioTemp { AudioStore.deleteTemp(audioTemp) }   // 텍스트 없으면 저장 안 함 → 임시 정리
            if let photoTemp { PhotoStore.deleteTemp(photoTemp) }
            return
        }
        let now = Date()
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; let date = f.string(from: now)
        f.dateFormat = "HH:mm";     let time = f.string(from: now)
        let id = UUID().uuidString
        var extra = ["device": CaptureDevice.currentLabel()]
        if let audioTemp, let name = AudioStore.finalize(temp: audioTemp, forId: id) {
            extra["audio"] = name   // 원본 음성 포인터(성역·불변)
        }
        if let photoTemp, let name = PhotoStore.finalize(temp: photoTemp, forId: id) {
            extra["photo"] = name   // 원본 사진 포인터(성역·불변)
        }
        let e = Event.create(id: id, hlc: tick(),
                             date: date, time: time, source: source, raw: raw, extra: extra)
        append(e)
    }

    // MARK: 자동 분류 (Claude API · 사양서 §0-A·§3)

    /// 미분류 항목을 Claude API로 분류(iPhone 직접 호출). 결과(type/due/resurface)를
    /// **기존 edit 이벤트 경로**로 기기 조각에 붙인다(엔진·직렬화 무변경). "당겨서 분류"·수동 버튼에서 호출.
    /// 키는 Keychain에서만 읽는다(§7). 성역(원문·수집시각·기기)은 절대 안 건드린다.
    /// - Parameter auto: true면 진행/결과를 **화면 중앙 토스트**(autoToast)로 알린다("당겨서 분류").
    ///   false(설정 수동 버튼)면 토스트 없이 classifyPhase만 갱신(설정 그 자리에서 표시).
    /// - Parameter runningToast: auto일 때 "분류하는 중…" 진행 토스트를 띄울지. "당겨서 분류"는
    ///   네이티브 새로고침 스피너가 이미 진행을 표시하므로 false로 껐다(중복 스피너 방지) — 완료/실패/없음
    ///   결과 토스트는 그대로 뜬다.
    func classifyUnclassified(auto: Bool = false, runningToast: Bool = true) async {
        if case .running = classifyPhase { return }
        guard let key = KeychainStore.loadAPIKey() else {
            classifyPhase = .failed("API 키가 없습니다. 설정에서 넣어 주세요.")
            if auto { autoToast = ClassifyToast(kind: .failure, text: "API 키가 없어요 — 설정에서 넣어 주세요") }
            return
        }
        let targets = unclassifiedItems.filter { !($0.raw ?? "").isEmpty }
        guard !targets.isEmpty else {
            classifyPhase = .done(0)
            if auto { autoToast = ClassifyToast(kind: .success, text: "분류할 새 기억이 없어요") }
            return
        }

        classifyPhase = .running
        if auto && runningToast { autoToast = ClassifyToast(kind: .running, text: "새 기억을 분류하는 중…") }
        let items = targets.enumerated().map { (index: $0.offset, raw: $0.element.raw ?? "") }
        do {
            let results = try await ClaudeClassifier.classify(items: items, apiKey: key)
            var events: [Event] = []
            for (i, item) in targets.enumerated() {
                // 반영 전 검증: type이 §2 분류 체계에 있어야만 씀. 어긋난 응답(빈 값·미지정 type)은
                // 그냥 건너뛰어 미분류로 남긴다(쓰레기 값이 항목에 안 써지도록).
                guard let c = results[i], let fields = classifyFields(c) else { continue }
                events.append(.edit(id: item.id, hlc: tick(), fields))
            }
            appendBatch(events)   // 재읽기·재병합 포함
            classifyPhase = .done(events.count)
            if auto {
                autoToast = events.isEmpty
                    ? ClassifyToast(kind: .success, text: "새로 분류된 기억이 없어요")
                    : ClassifyToast(kind: .success, text: "새 기억 \(events.count)개를 분류했어요")
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            classifyPhase = .failed(msg)
            if auto { autoToast = ClassifyToast(kind: .failure, text: "자동 분류 실패 — 설정에서 확인") }
        }
    }

    /// §2 분류 체계(type)의 유효값. 이 밖의 값은 반영하지 않는다(방어).
    private static let validTypes: Set<String> =
        ["event", "promise", "info-action", "info", "idea", "principle", "discard"]

    /// 분류 결과 → **검증 통과한** 안전한(공백 없는) 필드만. 반영 불가면 nil(→ 미분류로 남김).
    /// - type이 §2 밖이면 nil.
    /// - **discard는 반영하지 않는다**: AI가 사람이 수집한 기억을 조용히 삭제(=삭제 취급)하면 안 됨.
    ///   미분류로 보존 → 사람이 직접 검토/삭제. (삭제는 단방향·사람 몫.)
    /// - due/resurface는 실제 YYYY-MM-DD로 파싱되는 것만 씀(weekly/none/깨진 값=시점 없음).
    /// - question(info-action 재확인 질문, 공백 있음)은 이제 fields.v1 편집 블록으로 직렬화된다
    ///   (그릇 Stage 1 — EventWriter/EventLog). 있으면 함께 쓴다. 이 이벤트는 question 때문에 자동으로
    ///   set→edit 블록으로 직렬화되며, 파서가 개별 필드로 펼쳐 병합에 반영(per-field LWW 그대로).
    private func classifyFields(_ c: Classification) -> [String: String]? {
        let type = c.type.trimmingCharacters(in: .whitespaces)
        guard Self.validTypes.contains(type), type != "discard" else { return nil }
        var f: [String: String] = ["type": type]
        if ItemSchedule.parseDay(c.due) != nil {       // 실제 날짜만 시점으로
            f["due"] = c.due
            if ItemSchedule.parseDay(c.resurface) != nil { f["resurface"] = c.resurface }
        }
        let q = c.question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { f["question"] = q }            // 공백 있어도 편집 블록이 담음(Stage 1)
        return f
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
