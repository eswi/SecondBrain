import XCTest
@testable import SecondBrainCore

/// **Stage 5-D (2026-08-06) — 알림 문구 세 톤.** 문구는 사용자가 정했다.
///
/// | 톤 | 문구 | 언제 |
/// |---|---|---|
/// | 재촉 · 예고 | 곧 챙길 것 | 완료를 요구하는 항목의 미리 알림 |
/// | 재촉 · 지금 | 지금 챙길 것 | 완료를 요구하는 항목의 마감/회차 |
/// | 통보 | 오늘 기억할 것 | 완료를 안 요구하는 것(자동 완성 있는 되풀이 — 생일·기일) |
///
/// 옛 제목 `"받은함 · 곧 닥칠 것"` 은 **화면에 없는 말이 둘**이었다("받은함" → 탭은 "새로운 기억",
/// "곧 닥칠 것" → 섹션은 "지금 챙길 것"). 2026-08-03에 Core 주석의 같은 오용은 정정했는데
/// **정작 사용자 눈에 닿는 이 문자열이 남아 있었다.** 아래 마지막 회귀선이 그 재발을 막는다.
final class NotificationToneTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(
        timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 8, day: 6, hour: 0))!
    private let roomy = NotificationBudget(total: 999, recurring: 999, plain: 999)

    private func make(_ id: String, type: String, due: String?, resurface: String? = nil,
                      recur: String? = nil, auto: String? = nil) -> ResolvedItem {
        var f: [String: String] = ["type": type, "raw": "원문 \(id)"]
        if let due { f["due"] = due }
        if let resurface { f["resurface"] = resurface }
        if let recur { f["recur"] = recur }
        if let auto { f["recurAuto"] = auto }
        return ResolvedItem(id: id, fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }

    private func titles(_ ps: [PlannedNotification]) -> [PlannedNotification.Kind: String] {
        Dictionary(ps.map { ($0.kind, $0.title) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: 재촉 두 톤 — 완료를 요구하는 것

    /// 약(자동완성 없음) — lead는 "곧", 회차는 "지금". **두 톤이 한 항목에서 같이 나온다.**
    func testMedication_leadAndDue_getTwoTones() {
        let it = make("약", type: "recurrence", due: "2026-08-06T08:00",
                      resurface: "2026-08-06T07:00", recur: "daily", auto: "none")
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        let first = Array(plan.prefix(2))
        XCTAssertEqual(titles(first)[.lead], "곧 챙길 것")
        XCTAssertEqual(titles(first)[.due], "지금 챙길 것")
    }

    /// **되풀이 특례가 아니다** — 일반 항목(할 일)도 같은 두 톤을 받는다.
    /// 미리 알림만 걸었을 때 정작 마감일에 조용하던 것은 되풀이만의 문제가 아니었다(5-A).
    func testPlainTask_getsTheSameTwoTones() {
        let it = make("일", type: "task", due: "2026-08-08T09:00", resurface: "2026-08-07T09:00")
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        XCTAssertEqual(titles(plan)[.lead], "곧 챙길 것")
        XCTAssertEqual(titles(plan)[.due], "지금 챙길 것")
    }

    /// lead 0 접힘 — 미리 알림이 없으면 회차 한 건이고 톤은 "지금".
    func testLeadFolded_onlyNowTone() {
        let it = make("약", type: "recurrence", due: "2026-08-06T08:00", recur: "daily", auto: "none")
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        XCTAssertEqual(plan.first?.kind, .due)
        XCTAssertEqual(plan.first?.title, "지금 챙길 것")
    }

    // MARK: 통보 톤 — 완료를 안 요구하는 것

    /// 생일(자동완성 있음) + lead → 한 건이고 **"오늘 기억할 것"**. 재촉하지 않는다.
    func testTelling_withLead_isNotUrging() {
        let it = make("생일", type: "recurrence", due: "2026-08-20T09:00",
                      resurface: "2026-08-17T09:00", recur: "yearly", auto: "endOfDay")
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.kind, .lead)
        XCTAssertEqual(plan.first?.title, "오늘 기억할 것")
    }

    /// **★ 경계 — 종류가 `.due`여도 통보면 통보다.** lead 없는 생일은 회차 지점 한 건을 내는데,
    /// 그 자리에 "지금 챙길 것"이 뜨면 **완료를 요구하지 않는 것을 재촉**하게 된다.
    /// 톤은 **종류가 아니라 "완료를 요구하는가"** 가 정한다.
    func testTelling_dueKind_stillTellingTone() {
        let it = make("기일", type: "recurrence", due: "2026-08-06T09:00", recur: "yearly", auto: "noon")
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.kind, .due)
        XCTAssertEqual(plan.first?.title, "오늘 기억할 것", "통보인데 재촉 톤이 나갔다")
    }

    // MARK: 체인과 정합 (5-C)

    /// 체인의 **뒷 회차도 같은 톤**이다 — 회차마다 문구가 흔들리면 안 된다.
    func testChainCyclesShareTheSameTones() {
        let it = make("약", type: "recurrence", due: "2026-08-06T08:00",
                      resurface: "2026-08-06T07:00", recur: "daily", auto: "none")
        let plan = NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
        XCTAssertGreaterThan(plan.count, 2, "체인이 여러 회차를 냈어야 한다")
        for p in plan {
            XCTAssertEqual(p.title, p.kind == .lead ? "곧 챙길 것" : "지금 챙길 것",
                           "\(p.cycleKey ?? "")에서 톤이 흔들렸다")
        }
    }

    // MARK: ★ 회귀선 — 화면에 없는 말이 알림으로 새어 나가지 않는다

    /// **옛 제목이 정확히 이 방식으로 새어 나갔다.** 2026-08-03 실기기 확인에서 *"화면에 없는 이름으로
    /// 대화하고 있었다"* 는 것이 드러나(섹션 "최근 들어온 것"은 존재하지 않았다) **Core 주석 3곳을 정정**했는데,
    /// **정작 사용자에게 나가는 문자열은 안 훑었다.** 대화에서 드러난 문제라 대화의 언어만 손보고 끝낸 것이다.
    /// 그래서 회귀선을 **문자열 쪽에** 건다. 앞으로 화면에 없는 말이 들어가면 여기서 걸린다.
    func testNoOffScreenWordsInAnyTitle() {
        let items = [
            make("약", type: "recurrence", due: "2026-08-06T08:00", resurface: "2026-08-06T07:00",
                 recur: "daily", auto: "none"),
            make("생일", type: "recurrence", due: "2026-08-20T09:00", recur: "yearly", auto: "endOfDay"),
            make("일", type: "task", due: "2026-08-08T09:00", resurface: "2026-08-07T09:00"),
            make("약속", type: "appointment", due: "2026-08-09T10:00"),
        ]
        let plan = NotificationPlanner.plan(items: items, now: now, calendar: utc, budget: roomy)
        XCTAssertFalse(plan.isEmpty)

        let allowed: Set<String> = ["곧 챙길 것", "지금 챙길 것", "오늘 기억할 것"]
        let banned = ["받은함", "곧 닥칠 것", "최근 들어온 것", "inbox"]
        for p in plan {
            XCTAssertTrue(allowed.contains(p.title), "정해지지 않은 문구가 나갔다: \(p.title)")
            for word in banned {
                XCTAssertFalse(p.title.contains(word), "화면에 없는 말이 알림에 들어갔다: \(word)")
            }
        }
    }

    /// **본문은 원문 그대로다** — 알림이 기억 자체를 보여준다(요약·가공 안 함).
    /// 원문이 없는 항목만 자리표시자.
    func testBodyIsTheRawText() {
        let it = make("약", type: "recurrence", due: "2026-08-06T08:00", recur: "daily", auto: "none")
        XCTAssertEqual(NotificationPlanner.plan(items: [it], now: now, calendar: utc, budget: roomy)
                        .first?.body, "원문 약")

        var f = it.fields; f["raw"] = nil
        let noRaw = ResolvedItem(id: "빈", fields: f, deleted: false, confirmed: false,
                                 createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
        XCTAssertEqual(NotificationPlanner.plan(items: [noRaw], now: now, calendar: utc, budget: roomy)
                        .first?.body, "(항목)")
    }
}
