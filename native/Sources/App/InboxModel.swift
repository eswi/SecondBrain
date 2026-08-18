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
    /// 연결된 폴더 이름(설정 화면이 보여준다). 못 열거나 안 골랐으면 빈 문자열.
    @Published private(set) var folderName = ""
    /// **폴더 연결 상태**(사양서 §0-A-1). 옛 `needsFolder`(Bool)를 대체한다 —
    /// 그건 "북마크 데이터가 있나"만 보는 **저장값 판정**이라 **"못 연다"를 원리적으로 못 잡았고**,
    /// 연결이 끊겨도 안내 화면에 도달조차 못 한 채 빈 목록이 떠 **기억이 사라진 것처럼 보였다.**
    @Published private(set) var folderLink: FolderLink = .notChosen
    /// 옛 이름 호환 — 화면이 "안내를 띄울지"를 이걸로 묻던 자리. 뜻이 넓어졌다(미선택 → 안내 필요).
    var needsFolder: Bool { folderLink.needsGuidance }
    /// 알림 예산 회계 한 줄(5-B) — 몇 건 등록됐고 **예산 때문에 몇 회차가 잘렸는지**.
    /// 지금은 확인 경로(디버그 화면이 읽거나 콘솔 로그)일 뿐 화면에 안 띄운다 — 보여줄 방법은 나중에 정한다.
    @Published var notifyBudget = ""

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

    /// **확정(`confirmed`)이 최상위 축, 그 아래가 시점(Due/Resurface).** 배타적·중복 없음:
    /// - **미확정 → 새 기억들** (시점이 있든 없든. 오래된 순 = 선입선출, 묻히지 않게)
    /// - 확정 + 시점 있음 → **지금 챙길 것** (완료되면 보관으로 흐름)
    /// - 확정 + 시점 없음 → **살아있는 기억** (시점 없는 것만이 살아있는 기억의 몫)
    /// 원칙(principle)은 어디에도 안 들어가고 별도 ambient 띠(`principles`).
    ///
    /// **★ 축이 바뀌었다 (2026-08-18).** 옛 규칙은 *"시점 있음 → 지금 챙길 것 (확정 무관)"* 이었다.
    /// **시점을 정하는 것은 결정이고 결정은 [기억하기]로 한다** → 미확정 항목에는 시점이 붙지 않는다
    /// (`memory-philosophy.md`). 그런데 **자동 분류가 붙인 시점**과 **레거시 웹 v0가 남긴 값**이 있어
    /// 미확정인데 시점을 가진 항목이 실제로 존재할 수 있다. 그것을 「지금 챙길 것」에 올리면
    /// **아무것도 안 보고 처리하라고 내미는 것**이 되므로, 확정 전에는 「새 기억들」에 남긴다.
    ///
    /// ⚠️⚠️ **「확정 축」 게이트는 셋이다 — 한쪽만 고치지 말 것.** 셋 다 `confirmed` 하나만 본다:
    /// | 자리 | 무엇을 막나 | 깨지면 |
    /// |---|---|---|
    /// | **`partition`** (여기) | **보여주기** — 「지금 챙길 것」에 안 올린다 | 화면이 이상해진다 |
    /// | **`notifiable`** | **알리기** — 알림을 안 건다 | 안 울려야 할 알림이 울린다 |
    /// | **`catchUpRecurrence`** | **필드 쓰기** — 회차를 안 전진시킨다 | **데이터가 조용히 바뀐다** ← 가장 위험 |
    /// 하나만 고치면 이 과제(「임시는 기억하기 전까지 아무것도 하지 않는다」)가 반쪽이 된다.
    /// 뜻의 정본은 `memory-philosophy.md` §2-1-B.
    struct Partition {
        var upcoming: [UpcomingEntry]
        var newMemories: [ResolvedItem]   // 미확정 전부(시점 유무 무관), 오래된 순
        var living: [ResolvedItem]         // 시점 없음 + 확정 (필터 전)
    }

    private var partition: Partition {
        let nonPrinciple = liveNonDone.filter { $0.type != "principle" }
        let base = InboxSectionizer.split(nonPrinciple, now: Date())
        // 시점이 있어도 미확정이면 「지금 챙길 것」에서 빼 「새 기억들」로 보낸다(위 규칙).
        let upcoming = base.upcoming.filter { $0.item.confirmed }
        let unconfirmedScheduled = base.upcoming.filter { !$0.item.confirmed }.map(\.item)
        let newMems = (base.recent.filter { !$0.confirmed } + unconfirmedScheduled)
            .sorted { a, b in a.createdHLC != b.createdHLC ? a.createdHLC < b.createdHLC : a.id < b.id }
        let living = base.recent.filter { $0.confirmed }   // recent는 MergeEngine 최신순 유지
        return Partition(upcoming: upcoming, newMemories: newMems, living: living)
    }

    /// **알림 대상 = 확정된 것만** (2026-08-18 · 방법 「나」).
    ///
    /// **왜 여기서 거르나:** `NotificationPlanner`(Core)는 `confirmed`를 안 본다 — Core에서 완료·확정 두 축은
    /// 직교하고, 그 직교를 깨면 헬퍼 기본값이 `confirmed: false`인 기존 시험이 무더기로 깨진다.
    /// 그래서 **게이트를 앱 레이어 한 곳**에 둔다.
    ///
    /// ⚠️⚠️ **「확정 축」 게이트 셋 중 하나다 — `partition`(보여주기) · 이것(알리기) ·
    /// `catchUpRecurrence`(필드 쓰기). 셋이 같은 조건을 봐야 한다.** 표는 `partition`의 주석에 있다.
    /// **한쪽만 고치지 말 것.**
    ///
    /// **§7 폴백(`ClassSpecCatalog.uses` = 정의 없는 분류는 전부 씀)과 부딪히지 않는다 — 축이 다르다.**
    /// §7은 **분류가 안 붙었다는 이유로** 사람이 적어둔 날짜를 버리지 말라는 것이고, 이것은
    /// **사람이 아직 승인하지 않은 동안** 알리지 않는다는 것이다. 값은 안 지운다 — [기억하기] 한 번으로
    /// 알림이 살아난다(**버림이 아니라 유보**). 자세한 것은 `memory-philosophy.md`.
    var notifiable: [ResolvedItem] { liveNonDone.filter { $0.confirmed } }

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
        #if DEBUG
        if !FragmentFolder.hasFolder, SampleData.useInSimulator {
            folderLink = .ok(files: 1)
            resolve(EventLog.parse(SampleData.text))
            return
        }
        #endif
        loadGen &+= 1
        let gen = loadGen
        // **상태는 읽어봐야 안다** — `hasFolder`(저장값)로 미리 가르지 않는다(사양서 §0-A-1).
        let (events, status, name) = await Self.readAndParse()
        guard gen == loadGen else { return }   // 그사이 더 최신 로드가 시작됨 → 낡은 결과 버림
        folderLink = status
        folderName = name
        guard case .ok = status else {
            // 못 연다·받는 중·비었다·안 골랐다 — **목록을 비우되 상태는 화면이 갈라 말한다.**
            liveNonDone = []; doneItems = []; trashed = []
            return
        }
        resolve(events)
    }

    /// 폴더의 조각을 읽고 파싱 — 전부 **메인 밖**(Task.detached). 순수 값(Event·FolderLink: Sendable)만 돌려준다.
    private static func readAndParse() async -> ([Event], FolderLink, String) {
        await Task.detached(priority: .userInitiated) {
            let (frags, status, name) = FragmentFolder.read()
            var events: [Event] = []
            for f in frags { events.append(contentsOf: EventLog.parse(f.text)) }
            return (events, status, name)
        }.value
    }

    /// 이벤트 배열을 병합해 상태에 반영(시계 전진·알림 재조정 포함).
    private func resolve(_ events: [Event]) {
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

        catchUpRecurrence()   // 되풀이 지난 회차 자동완성(자동완성 있는 것만, 멱등) — 앱 열 때/행동 후
        scheduleNotifications()
    }

    /// 되풀이 회차 전진 패스 — 두 가지를 본다. 둘 다 멱등(전진 뒤 재실행하면 더 안 바뀜 → 재로드로 수렴).
    /// 1. **켠 직후 보정**(`resumeChanges`) — 꺼둔 기간에 지나간 회차만큼만 전진. 꺼두기 전 놓침은 보존.
    /// 2. **자동완성 catch-up**(`catchUpChanges`) — 자동 완성이 있으면 지나간 회차를 자동 전진. `none`이면 안 함(쌓임).
    ///
    /// 한 항목에 둘이 겹치면 **이번 로드는 1만** 한다 — 둘 다 같은 옛 마감에서 전진량을 계산하므로
    /// 합치면 이중 전진이 된다. 1을 반영한 재로드에서 2가 갱신된 마감으로 다시 계산해 이어받는다.
    ///
    /// **★ 확정된 것만 전진시킨다 (2026-08-18).** 근거는 `memory-philosophy.md` **§2-1-B** —
    /// *시점을 정하는 것은 결정이고, 결정은 [기억하기]로 한다. 따라서 미확정 항목에는 시점이 붙지 않는다.*
    /// 옛 코드는 `liveNonDone where type == "recurrence"`만 보고 **`confirmed`를 안 봤다.**
    ///
    /// **⚠️ 이 자리는 「확정 축」 게이트 셋 중 성격이 다르다 — 여기는 필드를 쓴다.**
    /// `partition`은 **보여주기**를, `notifiable`은 **알리기**를 막는다. 둘은 깨져도 화면·알림이 이상해질 뿐
    /// **데이터는 그대로**다. **이 자리가 깨지면 사람이 안 본 사이에 마감·미리 알림이 조용히 전진한다** —
    /// 앱을 열기만 해도 일어나고, 되돌릴 단추가 없다. **셋 중 가장 조용히 틀리는 자리다.**
    private func catchUpRecurrence() {
        let now = Date()
        var edits: [Event] = []
        // `confirmed`: 확정 축 게이트 셋 중 **필드를 쓰는** 자리(위 주석). `partition`·`notifiable`과 같은 조건.
        for it in liveNonDone where it.type == "recurrence" && it.confirmed {
            if let resume = Recurrence.resumeChanges(it, now: now) {     // 켠 직후 보정이 우선
                edits.append(.edit(id: it.id, hlc: tick(), resume)); continue
            }
            if let changes = Recurrence.catchUpChanges(it, now: now) {   // 마감·미리 알림 둘 다 전진
                edits.append(.edit(id: it.id, hlc: tick(), changes))
            }
        }
        appendBatch(edits)   // 비어 있으면 내부에서 무시 → 재귀 종료
    }

    /// 현재 살아있는 항목의 resurface/due 날짜로 로컬 알림 재조정(멱등).
    /// 파일이 진실원 → 매 로드/행동마다 계획을 다시 계산해 시스템 알림과 일치시킨다.
    private func scheduleNotifications() {
        // 실제 폴더(진실원)가 있을 때만. 샘플/시뮬레이터(폴더 없음)에선 알림 요청·스케줄 안 함.
        guard FragmentFolder.hasFolder else { return }
        // **확정된 것만 알린다**(`notifiable` — 2026-08-18). `liveNonDone`을 그대로 넘기면
        // 「지금 챙길 것」에서 뺀 미확정 항목이 알림으로 새어나간다.
        let result = NotificationPlanner.planned(items: notifiable, now: Date())
        // **잘린 것이 보여야 한다**(5-B) — 알림은 안 오는 것을 눈치채기 어려워 특히 위험하다.
        // 확인 경로는 여기 하나로 모은다: 상태(`notifyBudget`, 나중에 디버그 화면이 읽으면 됨) + 콘솔 로그.
        // 사용자에게 어떻게 보여줄지는 아직 안 정했다 — 지금은 "확인이 가능하다"까지만.
        notifyBudget = result.summary
        if result.droppedCycles > 0 { print("[알림예산] \(result.summary)") }
        Task { await NotificationScheduler.reschedule(result.scheduled) }
    }

    /// 문서 피커로 고른 폴더를 등록하고 즉시 로드.
    func setFolder(_ url: URL) {
        try? FragmentFolder.saveBookmark(for: url)
        load()
    }

    // MARK: 항목 행동 → 이벤트 append

    func delete(_ item: ResolvedItem)   { append(.delete(id: item.id, hlc: tick())) }
    /// 완료 — **분류로 분기**(Stage 3). 되풀이=마지막 완료 시점만(항목 살아있음) / 그 외=status=done(보관함행).
    /// - Returns: **실제로 쓴 변경**(빈 dict = 아무것도 안 씀). 화면이 draft를 같이 옮기는 데 쓴다
    ///   (`EditDiff.draftSync` — 2026-08-06 `가`: 화면이 안 따라가서 낡은 값 위에 부분 저장이 났다).
    @discardableResult
    func markDone(_ item: ResolvedItem) -> [String: String] {
        let changes = Recurrence.completionChanges(for: item, now: Date())
        // **이미 닫은 회차면 빈 변경**(재완료 멱등, D-3 (a)) → 이벤트를 쓰지 않는다.
        // `append`는 `appendBatch`와 달리 빈 것을 안 걸러내므로, 안 막으면 누를 때마다 빈 `edit` 줄이 쌓인다.
        guard !changes.isEmpty else { return [:] }
        append(.edit(id: item.id, hlc: tick(), changes))
        return changes
    }

    /// 되풀이 완료 취소 — 완료가 바꾼 **lastDone·lastDoneDue·마감·미리 알림을 전부 직전 값으로 되돌린다**
    /// (streak·회차 보존).
    ///
    /// **`lastDoneDue`도 반드시 함께 되돌린다**(2026-08-05) — 안 되돌리면 마감만 과거로 가고 증인은 미래를
    /// 가리켜 등식이 어긋난 채 남는다. 되돌릴 직전 값이 없으면(첫 완료의 취소) **빈 값으로 지운다** —
    /// 낡은 등식을 남기느니 옛 항목 폴백으로 내려보내는 쪽이 안전하다. (`lastDone`과 같은 규약.)
    /// - Returns: **실제로 되돌린 변경**. `markDone`과 같은 이유로 화면이 draft를 같이 되돌리는 데 쓴다.
    ///   직전 값이 없는 칸은 dict에 안 담긴다 = "그 칸은 안 움직였다"(화면도 안 건드려야 한다).
    @discardableResult
    func undoRecurComplete(_ item: ResolvedItem) -> [String: String] {
        var changes: [String: String] =
            [Recurrence.lastDoneKey: Recurrence.priorValue(in: allEvents, id: item.id, key: Recurrence.lastDoneKey) ?? "",
             Recurrence.lastDoneDueKey: Recurrence.priorValue(in: allEvents, id: item.id, key: Recurrence.lastDoneDueKey) ?? ""]
        if let priorD = Recurrence.priorValue(in: allEvents, id: item.id, key: "due") { changes["due"] = priorD }
        if let priorR = Recurrence.priorValue(in: allEvents, id: item.id, key: "resurface") { changes["resurface"] = priorR }
        // **당김 기록도 같이 되돌린다**((c), 2026-08-08). 완료가 미리 알림을 당겼다면 그 완료를 취소할 때
        // 값은 돌아가는데 기록만 남는다 → **배너가 "…으로 맞췄어요"라고 없는 사실을 말한다.**
        // 직전 값이 없으면(그 완료가 처음 쓴 것) 빈 값 = 지움. `lastDone`과 같은 규약.
        changes[Recurrence.leadClampedKey] =
            Recurrence.priorValue(in: allEvents, id: item.id, key: Recurrence.leadClampedKey) ?? ""
        append(.edit(id: item.id, hlc: tick(), changes))
        return changes
    }

    /// 미루기(+7일) — 규칙 1(**시각 인지**, 2026-08-03)을 지키며 미룬다. 위반 상태로 저장하지 않는다.
    /// 상한은 미리 알림에 **시각이 있으면 마감 당일**, **없으면 마감 하루 전**이다(`resurfaceUpperBound`).
    /// - 마감이 가까우면 그 상한까지 당겨서 미루고 알린다. 상한이 오늘/과거면 미루지 않고 알린다.
    /// - 미리 알림을 안 쓰는 분류(정보·아이디어·원칙)에선 미루기가 무의미 → UI에서 액션을 숨겼지만(1차 방어),
    ///   여기서도 조용히 막는다(휴면 값이 써지지 않게). 근거: §7(a) — 못 쓰는 칸은 회색으로 두지 않고 없앤다.
    func defer7(_ item: ResolvedItem) {
        guard ClassSpecCatalog.uses(item.type, .resurface) else { return }   // 안전망(액션 숨김이 1차)
        // **⛔ 임시(미확정)면 미루지 않는다** (edit-policy.md §1-A, 2026-08-14) — 미루기는 미리 알림을
        // 새로 정하는 것이고, 시점은 기억하기 뒤에만 정할 수 있다. 화면에서도 액션을 빼지만(1차)
        // 여기서도 막는다 — 경로가 셋(새 기억들 컨텍스트·지금 챙길 것 스와이프·지금 챙길 것 컨텍스트)이다.
        guard (current(item.id) ?? item).confirmed else { return }
        switch ItemSchedule.deferSevenDays(due: item.due, now: Date(), resurfaceHasTime: ItemSchedule.timeOfDay(item.resurface ?? "") != nil) {
        case .deferred(let day, let capped):
            // 미루기는 날짜만 새로 정하고, 원래 미리 알림의 **시각은 보존**한다(§6-B). 시각 없던 값은 날짜만.
            append(.edit(id: item.id, hlc: tick(), ["resurface": ItemSchedule.withTimeOfDay(day, from: item.resurface)]))
            if capped {
                // "하루 전"을 뺐다(미결 3번, 2026-08-07) — 시각 있는 미리 알림이면 상한이 **마감 당일**이라 거짓이었다.
                // 상세의 같은 문구(`DetailView.deferResurface`)와 **글자까지 같게** 유지할 것.
                autoToast = ClassifyToast(kind: .success,
                    text: "마감이 가까워 미리 알림을 \(Self.korShort(day))로 맞췄어요")
            }
        case .blocked:
            // cap(상한)이 아니라 **마감**을 말한다 — 사람이 아는 값이고, 규칙 서술이 필요 없다.
            autoToast = ClassifyToast(kind: .failure,
                text: "마감(\(korDateTime(item.due ?? "")))이 가까워 더 미룰 수 없어요")
        }
    }

    /// "YYYY-MM-DD"(또는 시각 붙은 "…THH:mm") → "M월 d일"(안내 문구용). 파싱 실패면 원문 그대로.
    static func korShort(_ ymd: String) -> String {
        let datePart = ymd.split(whereSeparator: { $0 == "T" || $0 == " " }).first.map(String.init) ?? ymd
        let p = datePart.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return ymd }
        return "\(m)월 \(d)일"
    }

    /// 분류(종류) 변경. 레거시(legacy: id) 항목에서도 같은 경로(=set type= 이벤트)로 동작.
    /// **override는 확정이 아니다**(edit-policy §2 귀결) — 여긴 confirm을 안 건다.
    ///
    /// **⛔ 임시(미확정) 항목은 분류를 바꿀 수 없다** (edit-policy.md §1-A, 2026-08-14).
    /// 분류는 "이 기억을 어떻게 쓸 것인가"를 정하는 일이고, 아직 기억할지 정하지 않은 조각에는
    /// 정할 자격이 없다(`memory-philosophy.md` §2-1-A). **화면에서도 회색으로 막지만 여기서도 막는다** —
    /// 경로가 여럿(상세 메뉴·새 기억들 글리프·지금 챙길 것 글리프)이라 화면만 막으면 새 경로가 샌다.
    func changeType(_ item: ResolvedItem, to type: String) {
        guard type != item.type else { return }
        guard (current(item.id) ?? item).confirmed else { return }   // 임시면 무시(안전망)
        append(.edit(id: item.id, hlc: tick(), ["type": type]))
    }

    /// **id로 현재 항목을 다시 집는다.** 상세 화면의 `item`은 화면을 열 때의 **스냅숏**이라
    /// 그 뒤 모델이 움직이면(완료·취소·외부 동기화·`catchUpRecurrence`의 배경 전진) 낡는다.
    /// **저장 검사처럼 "저장될 최종 상태"를 알아야 하는 자리**는 스냅숏이 아니라 이것을 봐야 한다
    /// (2026-08-06 `가` — 검사한 쌍은 적법했는데 저장되는 쌍이 위반이었다).
    /// 못 찾으면 nil — 부르는 쪽이 스냅숏으로 폴백한다(항목이 완료·삭제로 목록에서 빠진 경우).
    func current(_ id: String) -> ResolvedItem? { liveNonDone.first { $0.id == id } }

    /// 상세 화면 draft 커밋(edit-policy §2 [저장]). 바뀐 필드를 **이벤트 1개**(단일 HLC)로 붙인다
    /// → "[저장] 한 번 = 이력 한 묶음". `changes`엔 confirmed가 없다(수정 ≠ 기억하기) — EditDiff가 보장.
    ///
    /// **⛔ 임시(미확정) 항목은 `raw`(원문)·`type`(분류)만 커밋된다** (edit-policy.md §1-A, 2026-08-14).
    /// 둘만 열린 이유: **식별**이다 — 원문을 못 읽으면 기억할지 판단할 수 없고(STT 오인식),
    /// 분류는 사람이 밟는 순서(원문 → 분류 → 기억하기)에서 판단의 일부다(`memory-philosophy.md` §2-1-A).
    /// 나머지(시점·반복)는 **버린다** — 화면에 아예 안 그려지므로 여기 오면 안 되지만 오더라도
    /// 조용히 떨어뜨린다(안전망). **성역은 애초에 `EditDiff`가 안 낸다**(`RawEditTests`).
    ///
    /// ⚠️ 임시 항목의 이 커밋은 **[기억하기]가 부른다**(상세에 [저장]이 없다 — §2 예외). `DetailView.remember()`.
    func commitEdits(_ item: ResolvedItem, changes: [String: String]) {
        var changes = changes
        if !(current(item.id) ?? item).confirmed {
            changes = changes.filter { $0.key == "raw" || $0.key == "type" }
        }
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
    /// - due/resurface는 실제 YYYY-MM-DD로 파싱되는 것만 씀(날짜 아닌 값=시점 없음).
    /// - question(info-action 재확인 질문, 공백 있음)은 이제 fields.v1 편집 블록으로 직렬화된다
    ///   (그릇 Stage 1 — EventWriter/EventLog). 있으면 함께 쓴다. 이 이벤트는 question 때문에 자동으로
    ///   set→edit 블록으로 직렬화되며, 파서가 개별 필드로 펼쳐 병합에 반영(per-field LWW 그대로).
    private func classifyFields(_ c: Classification) -> [String: String]? {
        let type = c.type.trimmingCharacters(in: .whitespaces)
        guard Self.validTypes.contains(type), type != "discard" else { return nil }
        var f: [String: String] = ["type": type]
        if ItemSchedule.parseDay(c.due) != nil {       // 실제 날짜만 시점으로
            f["due"] = c.due
            // 규칙 1: 미리 알림이 마감과 같거나 늦으면(마감 미래 기준) 미리 알림을 쓰지 않는다.
            // 프롬프트 지시(§3)만으로는 새던 위반값을 코드가 최종적으로 막는다.
            if ItemSchedule.parseDay(c.resurface) != nil,
               !ItemSchedule.violatesRule1(resurface: c.resurface, due: c.due, now: Date()) {
                f["resurface"] = c.resurface
            }
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
}
