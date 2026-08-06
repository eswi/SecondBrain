import XCTest
@testable import SecondBrainCore

/// **Stage 5-C (2026-08-06) — 체인(다음 K회차) · 호라이즌 = 시간 창 D × 예산.**
///
/// 여기서 닫는 것:
/// - **구멍 1** — 자동완성 없는 되풀이(약)는 마감이 전진하지 않아 **미래 지점이 없어 알림이 영구히 끊겼다**
///   (2026-08-04 실측: 되풀이 3개 중 2개가 슬롯 0). 하필 "약을 3일 놓친 것"이 이 설계의 출발점인데
///   구조가 정확히 그 경우에 침묵했다.
/// - **호라이즌** — 회차 수가 아니라 **시간 창**으로 자른다. 매일은 D회차, 매주·매년은 1회차(옛 동작 그대로).
/// - **★ 회차를 계산만 하고 저장하지 않는다** — 이게 이 스테이지에서 가장 위험한 자리다(아래 회귀선).
final class NotificationChainTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    /// 2026-08-06 00:00 UTC — 창(D=7)의 끝은 2026-08-13 00:00.
    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(
        timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 8, day: 6, hour: 0))!

    private func item(_ id: String, unit: String, due: String, resurface: String? = nil,
                      auto: String = "none") -> ResolvedItem {
        var f: [String: String] = ["type": "recurrence", "recur": unit, "due": due,
                                   "recurAuto": auto, "raw": "약 \(id)"]
        if let resurface { f["resurface"] = resurface }
        return ResolvedItem(id: id, fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }

    /// 넉넉한 예산 — 창이 무엇을 정하는지만 보고 싶을 때(예산이 먼저 걸리면 창을 못 본다).
    private let roomy = NotificationBudget(total: 999, recurring: 999, plain: 999)

    private func days(_ ps: [PlannedNotification]) -> [String] {
        ps.map { ItemSchedule.dayString($0.fireDate, calendar: utc) }
    }

    // MARK: ★ 회귀선 — 체인은 회차를 **계산만** 한다

    /// **체인이 회차를 전진시켜도 저장값·놓침은 그대로다.**
    ///
    /// 이 전진이 이벤트로 나가면 **놓침이 사라져 자동완성 "없음"의 뜻이 깨진다** — 약이 쌓여야
    /// "3일 놓침"이 뜨는데, 알림을 계획했다는 이유로 조용히 0이 되면 이 설계의 출발점이 무너진다.
    /// `catchUpChanges`·`resumeChanges`가 완료 필드를 안 쓴다는 회귀선과 같은 결이다.
    func testChainNeverAdvancesStoredCycle_missedSurvives() {
        // 마감이 3일 전(08-03), 자동완성 없음 → 놓침 3이 쌓여 있는 상태.
        let it = item("약", unit: "daily", due: "2026-08-03T08:00")
        XCTAssertEqual(Recurrence.missed(it, now: now, calendar: utc), 3)

        let r = NotificationPlanner.planned(items: [it], now: now, calendar: utc, budget: roomy)
        XCTAssertFalse(r.scheduled.isEmpty, "체인이 미래 회차를 냈어야 한다")

        // 계획을 세운 **뒤에도** 저장값과 놓침이 그대로여야 한다.
        XCTAssertEqual(it.due, "2026-08-03T08:00", "체인이 저장된 마감을 건드렸다")
        XCTAssertEqual(Recurrence.missed(it, now: now, calendar: utc), 3, "체인이 놓침을 지웠다")
        XCTAssertNil(Recurrence.catchUpChanges(it, now: now, calendar: utc),
                     "자동완성 없음인데 전진 변경이 생겼다")
    }

    /// 같은 것을 **여러 번 계획해도** 결과가 흔들리지 않는다(순수 함수 · 멱등).
    func testChainIsPureAndDeterministic() {
        let it = item("약", unit: "daily", due: "2026-08-03T08:00")
        let a = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        let b = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        XCTAssertEqual(a.map(\.requestKey), b.map(\.requestKey))
        XCTAssertEqual(a.map(\.fireDate), b.map(\.fireDate))
    }

    // MARK: 구멍 1 — 놓친 되풀이가 되살아난다

    /// **마감이 지난 약도 알림을 받는다.** 5-B까지는 미래 지점이 없어 **0건**이었다(실측에서 슬롯 0).
    /// 체인은 지난 회차를 건너뛰고 **첫 미래 회차부터** 시작한다.
    func testMissedRecurrence_getsFutureNotifications() {
        let it = item("약", unit: "daily", due: "2026-08-03T08:00")   // 3일 지남
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)

        XCTAssertFalse(plan.isEmpty, "놓친 되풀이가 여전히 침묵한다 — 구멍 1이 안 닫혔다")
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > now }, "지난 회차가 계획에 들어갔다")
        // 첫 발화는 **오늘(08-06) 08:00** — 08-03·04·05는 건너뛰고 첫 미래 회차부터.
        XCTAssertEqual(plan.first?.fireDate,
                       utc.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                                     year: 2026, month: 8, day: 6, hour: 8)))
    }

    // MARK: 호라이즌 = 시간 창 — 주기가 제 몫을 한다

    /// 매일 → 창(D=7) 안의 회차 전부. 08-06..08-13 중 마감이 창 끝(08-13 00:00) 이하인 것.
    func testDaily_fillsTheWindow() {
        let it = item("약", unit: "daily", due: "2026-08-06T08:00")
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        XCTAssertEqual(days(plan), ["2026-08-06", "2026-08-07", "2026-08-08", "2026-08-09",
                                    "2026-08-10", "2026-08-11", "2026-08-12"])
    }

    /// **매주는 1회차** — 옛 동작 그대로. 창이 7일이라 다음 회차(+7일)는 밖이다.
    /// 라운드 수로 잘랐다면 여기서 7주 치가 등록됐을 것이다.
    func testWeekly_staysOneCycle() {
        let it = item("습관", unit: "weekly", due: "2026-08-07T08:00")
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        XCTAssertEqual(days(plan), ["2026-08-07"])
    }

    /// **매년은 1회차** — 첫 회차가 창 밖이어도 **반드시 하나는 낸다.**
    /// 안 그러면 생일·기일이 0회차가 되어 옛 동작에서 후퇴한다(라운드로빈의 약속을 창에서도 지킨다).
    func testYearly_firstCycleAlwaysEmitted_evenBeyondWindow() {
        let it = item("생일", unit: "yearly", due: "2026-12-25T09:00", auto: "endOfDay")
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        XCTAssertEqual(days(plan), ["2026-12-25"])
    }

    /// lead가 있으면 회차마다 **두 건**이 같이 간다(묶음은 안 쪼개진다).
    func testChain_carriesLeadEveryCycle_leadPreserved() {
        let it = item("약", unit: "daily", due: "2026-08-06T08:00", resurface: "2026-08-06T07:00")
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)

        let byCycle = Dictionary(grouping: plan) { $0.cycleKey ?? "" }
        XCTAssertEqual(byCycle.count, 7)
        for (key, points) in byCycle {
            XCTAssertEqual(Set(points.map(\.kind)), [.lead, .due], "\(key)가 반쪽만 나왔다")
            let lead = points.first { $0.kind == .lead }!.fireDate
            let due  = points.first { $0.kind == .due }!.fireDate
            XCTAssertEqual(due.timeIntervalSince(lead), 3600, "\(key)에서 lead 1시간이 안 지켜졌다")
        }
    }

    // MARK: 식별자 — 회차마다 갈린다

    /// 안 갈면 **뒤의 등록이 앞의 것을 덮어써** 체인이 조용히 한 건으로 줄어든다(5-A에서 종류를 가른 이유와 같다).
    func testRequestKeysAreUniquePerCycle() {
        let it = item("약", unit: "daily", due: "2026-08-06T08:00", resurface: "2026-08-06T07:00")
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        XCTAssertEqual(Set(plan.map(\.requestKey)).count, plan.count, "식별자가 겹쳐 덮어쓰기가 난다")
        XCTAssertEqual(plan.first?.requestKey, "약:2026-08-06:lead")
    }

    // MARK: 꺼둠 · 창 밖의 경계

    /// 꺼둔 되풀이는 체인도 안 만든다 — 배너의 "알림 멈춤" 약속(E절)이 체인 뒤에도 그대로.
    func testDormant_producesNoChain() {
        var f = item("약", unit: "daily", due: "2026-08-06T08:00").fields
        f["recurPaused"] = "true"
        let it = ResolvedItem(id: "약", fields: f, deleted: false, confirmed: false,
                              createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
        XCTAssertTrue(NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy).isEmpty)
    }

    /// **주기가 없으면 체인이 없다** — 회차가 정의되지 않으므로 옛 경로(현재 회차 하나)로 떨어진다.
    /// (되풀이인데 주기 미설정 = "회차가 안 도는" 상태. §3-A가 배너로 안내하는 그 경우.)
    func testNoUnit_fallsBackToSingleCycle() {
        var f = item("약", unit: "daily", due: "2026-08-06T08:00").fields
        f["recur"] = ""
        let it = ResolvedItem(id: "약", fields: f, deleted: false, confirmed: false,
                              createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        XCTAssertEqual(days(plan), ["2026-08-06"])
        XCTAssertNil(plan.first?.cycleKey, "체인이 아닌데 회차 키가 붙었다")
    }

    /// 일반 항목은 **안 변한다** — 체인은 되풀이만의 것이다(회귀).
    func testPlainItemsUnaffected() {
        let it = ResolvedItem(id: "일", fields: ["type": "task", "due": "2026-08-08T09:00", "raw": "일"],
                              deleted: false, confirmed: false,
                              createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        XCTAssertEqual(days(plan), ["2026-08-08"])
        XCTAssertNil(plan.first?.cycleKey)
    }

    // MARK: 라운드로빈 — 체인이 길어도 어떤 항목도 0회차가 되지 않는다

    /// 한 항목의 체인이 몫을 다 먹으면 다른 항목이 영구히 밀린다. 라운드로빈이 그걸 막는다.
    func testRoundRobin_noItemGetsZeroCycles() {
        // 반복 몫 6 = 2슬롯 묶음 3개. 항목 3개가 각각 한 회차씩 가져가야 한다.
        let budget = NotificationBudget(total: 6, recurring: 6, plain: 0)
        let items = ["a", "b", "c"].map {
            item($0, unit: "daily", due: "2026-08-06T08:00", resurface: "2026-08-06T07:00")
        }
        let r = NotificationPlanner.planned(items: items, now: now, calendar: utc, budget: budget)
        XCTAssertEqual(Set(r.scheduled.map(\.id)), ["a", "b", "c"])
        XCTAssertEqual(r.droppedFirstRoundCycles, 0, "첫 회차를 못 받은 항목이 있다")
    }
}
