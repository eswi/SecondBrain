import XCTest
@testable import SecondBrainCore

/// **(c) — 어긋난 lead가 회차마다 자기 복제하는 것을 끊는다.** (2026-08-08)
///
/// **무엇이 문제였나:** `advanceBy`는 마감과 미리 알림을 **같은 k회** 전진시킨다(lead 보존).
/// 그런데 lead가 **뒤집혀 있어도**(미리 알림이 마감보다 늦어도) 그대로 옮긴다.
/// 뒤집힌 lead는 마감이 **과거**일 때 정당하게 생긴다 — 그때는 규칙 1이 자고 있다(`guard dd > now`,
/// 지난 것을 미루려면 필요한 느슨함). 문제는 **전진이 그 쌍을 미래로 옮긴다**는 것이다.
/// 미래에서는 규칙 1이 깨어 있는데, 이 경로는 [저장] 검사를 안 탄다
/// (`markDone`이 `append(.edit(...))`로 바로 쓴다) → **위반이 검사 없이 들어간다.**
///
/// **세 경로가 다 같은 `advanceBy`를 쓴다** — 완료 · 자동 완성(catch-up) · 꺼두기 켜기(resume).
/// 그래서 clamp도 `advanceBy` 한 곳에 둔다. 셋에 각각 시험을 두는 것은 **한 곳에 뒀다는 것 자체**를
/// 지키기 위해서다(누가 나중에 복사하면 여기서 갈린다).
///
/// **⚠️ 이 파일은 단계 0이다** — `PickerBoundRemovedTests`(B)와 갈리는 지점이 여기다.
/// B는 판정 로직을 안 바꿔서 어떤 시험도 고치기 전에 통과했다(= 거짓 안심).
/// (c)는 **`advanceBy`의 결과값이 실제로 달라진다** → 안 고치면 아래 시험들이 **실패한다.**
final class LeadClampTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func d(_ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: day, hour: h, minute: min))!
    }
    private func item(_ unit: String, due: String, resurface: String? = nil,
                      auto: String? = nil, paused: String? = nil, pausedAt: String? = nil,
                      clamped: String? = nil) -> ResolvedItem {
        var f: [String: String] = ["type": "recurrence", "recur": unit, "due": due, "raw": "약"]
        if let resurface { f["resurface"] = resurface }
        if let auto { f["recurAuto"] = auto }
        if let paused { f["recurPaused"] = paused }
        if let pausedAt { f["recurPausedAt"] = pausedAt }
        if let clamped { f[Recurrence.leadClampedKey] = clamped }
        return ResolvedItem(id: "a", fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }
    /// 전진 결과가 규칙 1을 지키는지 — 이 파일의 공통 판정.
    private func violates(_ c: [String: String]?, now: Date) -> Bool {
        guard let c, let r = c["resurface"], let due = c["due"] else { return false }
        return ItemSchedule.violatesRule1(resurface: r, due: due, now: now, calendar: utc)
    }

    // MARK: ★ 판정선 — 세 경로 전부

    /// **완료.** `가`(AF9BAB30)가 2026-08-08 아침까지 실제로 갖고 있던 모양이다:
    /// 마감 `08-07 13:00` · 미리 알림 `08-08 12:00`(lead −23시간).
    /// 안 고치면 전진 결과가 마감 `08-08 13:00` · 미리 알림 `08-09 12:00` — **뒤집힘이 그대로 복제된다.**
    func testCompletion_invertedLead_isClamped() {
        let now = d(8, 8, 9)
        let c = Recurrence.completionAdvance(item("daily", due: "2026-08-07T13:00",
                                                  resurface: "2026-08-08T12:00"), now: now, calendar: utc)
        XCTAssertEqual(c?["due"], "2026-08-08T13:00")
        XCTAssertFalse(violates(c, now: now), "전진 결과가 규칙 1을 어기면 안 된다")
        // 날짜를 상한(마감 당일)으로 당기되 **사람이 정한 시각 12:00은 보존**한다(§6-B).
        XCTAssertEqual(c?["resurface"], "2026-08-08T12:00")
    }

    /// **자동 완성(catch-up)** — 사람이 아무것도 안 눌러도 앱을 열면 돈다. 같은 clamp가 걸려야 한다.
    func testCatchUp_invertedLead_isClamped() {
        let now = d(8, 8, 9)
        let c = Recurrence.catchUpChanges(item("daily", due: "2026-08-07T13:00",
                                               resurface: "2026-08-08T12:00", auto: "endOfDay"),
                                          now: now, calendar: utc)
        XCTAssertNotNil(c?["due"])
        XCTAssertFalse(violates(c, now: now), "catch-up도 위반을 만들면 안 된다")
    }

    /// **꺼두기 켜기(resume)** — 꺼둔 동안 지나간 회차만큼 전진한다. 여기도 같은 clamp.
    ///
    /// ⚠️ **꺼둔 시점이 첫 회차보다 앞이어야 이 시험이 판정선이 된다.** resume은 **꺼둔 구간의 회차만**
    /// 건너뛰므로(이전 놓침 보존), 꺼두기 전에 이미 회차가 지났으면 전진해도 마감이 **과거**에 떨어지고
    /// 그러면 규칙 1이 자고 있어 clamp 조건이 아예 안 생긴다(첫 판 시험이 그래서 그냥 통과했다 —
    /// G-3을 두 번 못 닫았던 것과 **같은 종류의 헛통과**다).
    /// 여기서는 `pausedAt`을 첫 회차(08-05 13:00) **이전**으로 두어 k=3 전진이 마감을 미래로 보낸다.
    func testResume_invertedLead_isClamped() {
        let now = d(8, 8, 9)
        let c = Recurrence.resumeChanges(item("daily", due: "2026-08-05T13:00",
                                              resurface: "2026-08-06T12:00",
                                              paused: "false", pausedAt: "2026-08-05T09:00"),
                                         now: now, calendar: utc)
        XCTAssertEqual(c?["due"], "2026-08-08T13:00", "마감이 미래여야 규칙 1이 깨어 있다")
        XCTAssertFalse(violates(c, now: now), "켜기 보정도 위반을 만들면 안 된다")
    }

    // MARK: 대조군 — 정상 lead는 **안 건드린다**

    /// ⚠️ **이게 대조군이다.** 위 셋만 보면 "고쳐서 안 어긴다"와 "원래 안 어긴다"가 안 갈린다.
    /// 정상 lead(마감 08:00 · 미리 알림 07:00)는 전진해도 **1시간 그대로** 보존돼야 한다.
    func testNormalLead_isPreservedUntouched() {
        let now = d(8, 3, 8, 5)
        let c = Recurrence.completionAdvance(item("daily", due: "2026-08-03T08:00",
                                                  resurface: "2026-08-03T07:00"), now: now, calendar: utc)
        XCTAssertEqual(c?["due"], "2026-08-04T08:00")
        XCTAssertEqual(c?["resurface"], "2026-08-04T07:00", "lead 1시간 보존 — clamp가 끼어들면 안 된다")
        XCTAssertNil(c?[Recurrence.leadClampedKey], "안 당겼으면 기록도 안 남는다")
    }

    /// **전진했는데도 마감이 여전히 과거면 clamp 안 한다** — 규칙 1이 자고 있는 자리를 깨우지 않는다.
    /// (지난 것을 미뤄 둔 상태를 앱이 임의로 당기면 그거야말로 조용한 변경이다.)
    func testStillPastDueAfterAdvance_noClamp() {
        // 꺼둔 시점이 첫 회차 **뒤**라 전진량이 모자라 마감이 여전히 과거로 떨어진다(k=2 → 08-07 13:00).
        let now = d(8, 8, 9)
        let c = Recurrence.resumeChanges(item("daily", due: "2026-08-05T13:00",
                                              resurface: "2026-08-06T12:00",
                                              paused: "false", pausedAt: "2026-08-06T00:00"),
                                         now: now, calendar: utc)
        XCTAssertEqual(c?["due"], "2026-08-07T13:00", "전진했지만 여전히 과거")
        XCTAssertNil(c?[Recurrence.leadClampedKey], "마감이 과거면 규칙 1이 안 깨어난다 → 당기지 않는다")
        XCTAssertEqual(c?["resurface"], "2026-08-08T12:00", "뒤집힌 lead가 **그대로** 옮겨간다 — 여기선 그게 맞다")
    }

    // MARK: 시각 다루기 — 날짜만 당겨도 되나, 시각까지 당겨야 하나

    /// 날짜를 상한으로 당기면 해결되는 경우 — **사람이 정한 시각은 그대로 둔다**(§6-B).
    func testDateClampSuffices_timeOfDayPreserved() {
        let now = d(8, 8, 9)
        let c = Recurrence.completionAdvance(item("daily", due: "2026-08-07T13:00",
                                                  resurface: "2026-08-08T12:00"), now: now, calendar: utc)
        XCTAssertEqual(c?["resurface"], "2026-08-08T12:00", "12:00은 사람이 정한 값이다")
    }

    /// 날짜를 당겨도 **같은 날 더 늦은 시각**이면 여전히 위반이다 → 마감 시각까지 당긴다.
    /// (미리 알림 = 마감은 규칙 1이 허용한다 — `RuleOneTimeTests.testTimed_equalDue_ok`.)
    func testSameDayButLaterTime_clampsToDeadline() {
        let now = d(8, 8, 9)
        let c = Recurrence.completionAdvance(item("daily", due: "2026-08-07T13:00",
                                                  resurface: "2026-08-08T23:00"), now: now, calendar: utc)
        XCTAssertEqual(c?["due"], "2026-08-08T13:00")
        XCTAssertEqual(c?["resurface"], "2026-08-08T13:00", "23:00은 마감 13:00보다 늦다 → 마감까지만")
        XCTAssertFalse(violates(c, now: now))
    }

    /// **시각 없는 미리 알림**은 날짜 단위 규칙(마감−1일)을 탄다. 시각을 만들어 붙이지 않는다.
    func testDateOnlyResurface_clampsToDayBefore() {
        let now = d(8, 8, 9)
        let c = Recurrence.completionAdvance(item("daily", due: "2026-08-07T13:00",
                                                  resurface: "2026-08-08"), now: now, calendar: utc)
        XCTAssertEqual(c?["resurface"], "2026-08-07", "마감 08-08의 하루 전")
        XCTAssertFalse(violates(c, now: now))
    }

    // MARK: 기록 — 배너가 읽을 값 (지우는 조건 ㄱ: 다음 회차 전진 때)

    /// 당겼으면 **맞춘 값**을 남긴다. 배너가 그 값을 그대로 말한다("…12:00으로 맞췄어요").
    func testClamp_recordsTheValueItSet() {
        let now = d(8, 8, 9)
        let c = Recurrence.completionAdvance(item("daily", due: "2026-08-07T13:00",
                                                  resurface: "2026-08-08T12:00"), now: now, calendar: utc)
        XCTAssertEqual(c?[Recurrence.leadClampedKey], "2026-08-08T12:00")
        XCTAssertEqual(c?[Recurrence.leadClampedKey], c?["resurface"], "기록과 실제 값이 갈리면 배너가 거짓말을 한다")
    }

    /// **다음 회차 전진 때 지운다**(지우는 조건 ㄱ) — 한 회차 동안만 보인다.
    /// 당길 일이 없는 전진은 기록을 **빈 값으로 덮는다**(멱등 — 안 지우면 영원히 남는다).
    func testNextAdvance_clearsTheRecord() {
        let now = d(8, 9, 14)
        let c = Recurrence.completionAdvance(item("daily", due: "2026-08-08T13:00",
                                                  resurface: "2026-08-08T12:00",
                                                  clamped: "2026-08-08T12:00"), now: now, calendar: utc)
        XCTAssertEqual(c?[Recurrence.leadClampedKey], "", "다음 전진이 기록을 지운다")
    }

    /// 완료 이벤트에도 그대로 실린다 — `completionChanges`가 `completionAdvance`를 그대로 얹으므로.
    /// (이 시험이 깨지면 clamp는 됐는데 **배너가 못 뜬다**.)
    func testCompletionChanges_carriesTheRecord() {
        let now = d(8, 8, 9)
        let c = Recurrence.completionChanges(for: item("daily", due: "2026-08-07T13:00",
                                                       resurface: "2026-08-08T12:00"), now: now, calendar: utc)
        XCTAssertEqual(c[Recurrence.leadClampedKey], "2026-08-08T12:00")
    }
}
