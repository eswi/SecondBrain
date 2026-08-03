import XCTest
@testable import SecondBrainCore

/// **꺼두기(`recurPaused`)가 실제로 멈추는지** — 2026-08-03.
///
/// 상세 배너가 "되풀이 꺼둠 — 알림·되살아나기 멈춤"이라고 약속하는데 세 경로에 가드가 없어
/// 셋 다 안 지켜지고 있었다(새 기능이 아니라 **이미 있던 거짓 약속**). 세 곳을 각각 고정한다:
/// 1. 알림 — `NotificationPlanner.plan`
/// 2. 게시 게이트 — `ItemSchedule.isPublished` (+ `InboxSectionizer`가 상속)
/// 3. 자동완성 catch-up — `Recurrence.catchUpChanges`
///
/// 그리고 **기존 항목 불변**을 같이 고정한다 — 가드는 `type == "recurrence" && recurPaused == "true"`
/// 둘 다일 때만 걸리므로, 필드 없음·`"false"`·다른 분류는 전부 평시 동작이어야 한다.
final class RecurrencePausedTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func d(_ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: day, hour: h, minute: min))!
    }
    /// 되풀이 항목. `paused`는 nil(필드 없음)·"true"·"false" 셋을 다 넣어볼 수 있게 문자열로 받는다.
    private func rec(_ id: String = "a", due: String, resurface: String? = nil,
                     auto: String? = nil, paused: String? = nil, pausedAt: String? = nil,
                     unit: String = "daily") -> ResolvedItem {
        var f: [String: String] = ["type": "recurrence", "recur": unit, "due": due, "raw": "약"]
        if let resurface { f["resurface"] = resurface }
        if let auto { f["recurAuto"] = auto }
        if let paused { f["recurPaused"] = paused }
        if let pausedAt { f["recurPausedAt"] = pausedAt }
        return ResolvedItem(id: id, fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }
    /// 되풀이가 **아닌** 항목에 `recurPaused`가 남아 있는 경우(오염 차단 확인용).
    private func plain(_ id: String = "p", due: String, paused: String? = nil) -> ResolvedItem {
        var f: [String: String] = ["type": "task", "due": due, "raw": "보고서"]
        if let paused { f["recurPaused"] = paused }
        return ResolvedItem(id: id, fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }

    // MARK: 술어 자체

    func testIsDormant_onlyRecurrenceAndOnlyTrue() {
        XCTAssertTrue(Recurrence.isDormant(rec(due: "2026-08-05T08:00", paused: "true")))
        XCTAssertFalse(Recurrence.isDormant(rec(due: "2026-08-05T08:00", paused: "false")))
        XCTAssertFalse(Recurrence.isDormant(rec(due: "2026-08-05T08:00")))              // 필드 없음(레거시)
        // 되풀이가 아니면 `recurPaused`가 "true"여도 무시 — 다른 분류로 오염되지 않는다.
        XCTAssertFalse(Recurrence.isDormant(plain(due: "2026-08-05", paused: "true")))
    }

    // MARK: 1. 알림

    func testPlan_dormantExcluded() {
        let now = d(8, 3)
        // 꺼둠 → 계획에서 빠진다. 안 꺼진 같은 항목은 그대로 들어온다.
        let off = NotificationPlanner.plan(items: [rec(due: "2026-08-05T08:00", paused: "true")],
                                          now: now, calendar: utc)
        XCTAssertTrue(off.isEmpty)
        let on = NotificationPlanner.plan(items: [rec(due: "2026-08-05T08:00", paused: "false")],
                                         now: now, calendar: utc)
        XCTAssertEqual(on.map { $0.id }, ["a"])
        XCTAssertEqual(on.first?.fireDate, d(8, 5, 8))
    }

    /// 꺼둔 되풀이만 빠지고 **나머지는 그대로** — 상한·정렬에 영향 없음.
    func testPlan_dormantDoesNotAffectOthers() {
        let now = d(8, 3)
        let items = [rec("A", due: "2026-08-04T08:00", paused: "true"),   // 빠짐
                     rec("B", due: "2026-08-06T08:00"),                    // 남음(필드 없음)
                     plain("C", due: "2026-08-05", paused: "true")]        // 남음(되풀이 아님)
        let plan = NotificationPlanner.plan(items: items, now: now, calendar: utc, hour: 9)
        XCTAssertEqual(plan.map { $0.id }, ["C", "B"])                     // 08-05 09:00, 08-06 08:00
    }

    // MARK: 2. 게시 게이트

    func testIsPublished_dormantFalse_evenWhenDue() {
        let now = d(8, 3, 14)
        // 마감·미리 알림 둘 다 이미 지났어도(평시라면 확실히 게시) 꺼둠이면 게시 안 함.
        let it = rec(due: "2026-08-03T08:00", resurface: "2026-08-03T07:00", paused: "true")
        XCTAssertFalse(ItemSchedule.isPublished(it, now: now, calendar: utc))
        // 켜면 게시된다 — 같은 날짜, 같은 시각.
        let on = rec(due: "2026-08-03T08:00", resurface: "2026-08-03T07:00", paused: "false")
        XCTAssertTrue(ItemSchedule.isPublished(on, now: now, calendar: utc))
    }

    /// 게시 안 된 항목은 **사라지지 않는다** — '최근 들어온 것'으로 옮겨가고 총 개수가 보존된다(§7(c)).
    func testSectionizer_dormantMovesToRecent_countPreserved() {
        let now = d(8, 3, 14)
        let items = [rec("A", due: "2026-08-03T08:00", paused: "true"),
                     rec("B", due: "2026-08-03T08:00")]
        let s = InboxSectionizer.split(items, now: now, calendar: utc)
        XCTAssertEqual(s.upcoming.map { $0.item.id }, ["B"])
        XCTAssertEqual(s.recent.map { $0.id }, ["A"])
        XCTAssertEqual(s.upcoming.count + s.recent.count, items.count)   // 총 개수 보존
    }

    // MARK: 3. 자동완성 catch-up

    func testCatchUp_dormantDoesNotAdvance() {
        let now = d(8, 5, 14)
        // 8/1 마감 + endOfDay면 평시엔 8/5까지 전진할 상황. 꺼둠이면 손대지 않는다(마감이 얼어 있음).
        let off = rec(due: "2026-08-01T08:00", resurface: "2026-08-01T07:00", auto: "endOfDay", paused: "true")
        XCTAssertNil(Recurrence.catchUpChanges(off, now: now, calendar: utc))
        // 켜면 밀린 만큼 한 번에 전진 — lead(1시간)도 같이 보존된다.
        let on = rec(due: "2026-08-01T08:00", resurface: "2026-08-01T07:00", auto: "endOfDay", paused: "false")
        let c = Recurrence.catchUpChanges(on, now: now, calendar: utc)
        XCTAssertEqual(c?["due"], "2026-08-05T08:00")
        XCTAssertEqual(c?["resurface"], "2026-08-05T07:00")
    }

    // MARK: 4. 놓침 — 꺼둔 동안은 세지 않는다

    /// 꺼두기 전에 3일 놓쳤고 그 뒤 2주를 꺼뒀다 → 계속 **3일**. "14일 놓침"이 붙으면 안 놓친 것을 놓쳤다고 하는 것.
    func testMissed_frozenWhilePaused() {
        // 마감 8/1 08:00, 8/4에 꺼둠(그때 놓침 = 8/1·8/2·8/3 = 3일), 지금은 8/18.
        let it = rec(due: "2026-08-01T08:00", paused: "true", pausedAt: "2026-08-04T09:00")
        XCTAssertEqual(Recurrence.missed(it, now: d(8, 4, 9), calendar: utc), 3)    // 꺼둔 그 순간
        XCTAssertEqual(Recurrence.missed(it, now: d(8, 18, 9), calendar: utc), 3)   // 2주 뒤에도 그대로
        // 안 꺼져 있었다면 계속 셌을 것 — 대조군.
        let on = rec(due: "2026-08-01T08:00")
        XCTAssertEqual(Recurrence.missed(on, now: d(8, 18, 9), calendar: utc), 17)
    }

    /// **켤 때 경계에서 숫자가 튀지 않는다** — 꺼둔 기간(14회차)만큼만 전진해 꺼두기 전 놓침 3일을 보존.
    func testResume_advancesOnlyPausedSpan_missedPreserved() {
        let now = d(8, 18, 9)
        // 켠 직후 상태: recurPaused=false 인데 recurPausedAt이 아직 남아 있다(전진은 로드 패스가 한다).
        let justOn = rec(due: "2026-08-01T08:00", resurface: "2026-08-01T07:00",
                         paused: "false", pausedAt: "2026-08-04T09:00")
        let c = Recurrence.resumeChanges(justOn, now: now, calendar: utc)
        XCTAssertNotNil(c)
        XCTAssertEqual(c?[Recurrence.pausedAtKey], "")          // 기록 비움
        // k = 17(지금 놓침) − 3(꺼둘 때 놓침) = 14 → 8/1 + 14일 = 8/15. lead 1시간 보존.
        XCTAssertEqual(c?["due"], "2026-08-15T08:00")
        XCTAssertEqual(c?["resurface"], "2026-08-15T07:00")

        // 전진 적용 후 놓침 = 꺼두기 전과 같은 3일(튐 없음).
        let after = rec(due: "2026-08-15T08:00", resurface: "2026-08-15T07:00")
        XCTAssertEqual(Recurrence.missed(after, now: now, calendar: utc), 3)
    }

    /// 멱등 — 전진 뒤(기록 비었음) 재실행하면 nil. 아직 꺼둠이면 아무것도 안 함.
    func testResume_idempotentAndOnlyWhenOn() {
        let now = d(8, 18, 9)
        XCTAssertNil(Recurrence.resumeChanges(rec(due: "2026-08-15T08:00"), now: now, calendar: utc))
        XCTAssertNil(Recurrence.resumeChanges(rec(due: "2026-08-15T08:00", paused: "false", pausedAt: ""),
                                             now: now, calendar: utc))
        // 아직 꺼둠 → 보정 안 함(켜야 한다).
        XCTAssertNil(Recurrence.resumeChanges(rec(due: "2026-08-01T08:00", paused: "true", pausedAt: "2026-08-04T09:00"),
                                             now: now, calendar: utc))
    }

    /// 같은 날 껐다 켰으면 전진 0 — 기록만 비운다(마감을 건드리지 않는다).
    func testResume_sameDayNoAdvance() {
        let c = Recurrence.resumeChanges(rec(due: "2026-08-03T08:00", paused: "false", pausedAt: "2026-08-03T09:00"),
                                        now: d(8, 3, 18), calendar: utc)
        XCTAssertEqual(c?[Recurrence.pausedAtKey], "")
        XCTAssertNil(c?["due"])
    }

    // MARK: 기존 항목 불변(레거시 회귀 고정)

    /// `recurPaused` 필드가 **없는** 되풀이(= 지금 저장된 전부)는 세 경로가 모두 평시 동작이어야 한다.
    func testLegacy_noPausedField_allThreeUnchanged() {
        let now = d(8, 5, 14)
        let it = rec(due: "2026-08-01T08:00", resurface: "2026-08-01T07:00", auto: "endOfDay")
        XCTAssertTrue(ItemSchedule.isPublished(it, now: now, calendar: utc))
        XCTAssertNotNil(Recurrence.catchUpChanges(it, now: now, calendar: utc))
        let future = rec(due: "2026-08-06T08:00")
        XCTAssertEqual(NotificationPlanner.plan(items: [future], now: now, calendar: utc).count, 1)
    }

    /// 이 변경 **전에** 꺼둔 항목(= `recurPausedAt` 없는 꺼둠)은 옛 동작으로 폴백 — 크래시·데이터 변화 없음.
    func testLegacy_pausedWithoutTimestamp_fallsBackToNow() {
        let it = rec(due: "2026-08-01T08:00", paused: "true")            // pausedAt 없음
        XCTAssertEqual(Recurrence.missed(it, now: d(8, 18, 9), calendar: utc), 17)   // 옛 동작(계속 셈)
        XCTAssertNil(Recurrence.resumeChanges(rec(due: "2026-08-01T08:00", paused: "false"),
                                             now: d(8, 18, 9), calendar: utc))       // 보정할 근거 없음 → 안 함
    }
}
