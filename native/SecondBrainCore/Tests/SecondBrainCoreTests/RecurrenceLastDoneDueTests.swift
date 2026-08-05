import XCTest
@testable import SecondBrainCore

/// **`lastDoneDue` — 완료가 회차를 옮긴 목적지** ((b) Stage 1, 2026-08-05).
///
/// Stage 1은 **쓰기 경로만**이다: 완료가 적고 취소가 되돌린다. **아무도 안 읽는다** → 동작 변화 0.
/// (판정 교체는 Stage 2. 그래서 이 파일엔 `doneThisCycle` 단정이 없다.)
///
/// "닫은 회차"가 아니라 "전진한 목적지"를 적는 이유는 `Recurrence.lastDoneDueKey` 주석에.
/// catch-up·resume이 이 필드를 안 쓴다는 구조 고정 = `RecurrenceHolesTests.testNet_catchUpAndResume...`.
final class RecurrenceLastDoneDueTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func d(_ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: day, hour: h, minute: min))!
    }
    private func h(_ w: Int64, _ c: Int) -> HLC { HLC(wallMillis: w, counter: c, deviceId: "i") }
    private func rec(due: String?, resurface: String? = nil, lastDone: String? = nil,
                     unit: String = "daily") -> ResolvedItem {
        var f: [String: String] = ["type": "recurrence", "recur": unit, "raw": "약"]
        if let due { f["due"] = due }
        if let resurface { f["resurface"] = resurface }
        if let lastDone { f[Recurrence.lastDoneKey] = lastDone }
        return ResolvedItem(id: "a", fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }
    private func changes(_ it: ResolvedItem, at now: Date) -> [String: String] {
        Recurrence.completionChanges(for: it, now: now, calendar: utc)
    }

    // MARK: 완료가 적는다

    /// ★ **핵심 불변식: 완료가 쓰는 `lastDoneDue`는 같은 완료가 쓴 `due`와 글자까지 같다.**
    /// 이게 성립해야 Stage 2의 판정이 등식 하나로 끝난다.
    func testCompletion_writesFieldIdenticalToNewDue() {
        for (label, now) in [("정시", d(8, 5, 8, 5)), ("이른", d(8, 5, 7, 30)), ("밀린", d(8, 5, 14))] {
            let c = changes(rec(due: "2026-08-05T08:00", resurface: "2026-08-05T07:00"), at: now)
            XCTAssertEqual(c[Recurrence.lastDoneDueKey], c["due"], "\(label) 완료 — 목적지와 마감이 같아야")
            XCTAssertNotNil(c["due"], "\(label) 완료 — 전제: 전진이 일어난다")
        }
    }

    /// **밀린 완료에서 k와 무관하다** — 이 설계의 출발점("3일 놓친 약을 오늘 먹기").
    /// 닫은 회차(08-02)를 적었다면 현재 마감(08-06)과의 거리 k=4를 데이터에서 알 수 없어 판정이
    /// 휴리스틱이 됐을 자리다. 목적지를 적으므로 등식 하나로 끝난다.
    func testCompletion_lateByDays_recordsDestinationNotClosedCycle() {
        let c = changes(rec(due: "2026-08-02T08:00", lastDone: "2026-07-30T08:00"), at: d(8, 5, 14))
        XCTAssertEqual(c["due"], "2026-08-06T08:00", "놓친 날은 건너뛴다(기존 동작)")
        XCTAssertEqual(c[Recurrence.lastDoneDueKey], "2026-08-06T08:00", "닫은 회차(08-02)가 아니라 목적지")
    }

    /// **값 형식은 `due`를 그대로 따른다** — date-only 되풀이에 없는 시각을 만들어 붙이지 않는다.
    func testCompletion_dateOnlyItem_keepsDateOnlyForm() {
        let c = changes(rec(due: "2026-08-05"), at: d(8, 5, 14))
        XCTAssertEqual(c["due"], "2026-08-06")
        XCTAssertEqual(c[Recurrence.lastDoneDueKey], "2026-08-06", "T를 강제하지 않는다")
        // 형식이 갈려도 비교는 parseDay로 하므로 같은 시점으로 읽힌다.
        XCTAssertEqual(ItemSchedule.parseDay("2026-08-06", calendar: utc),
                       ItemSchedule.parseDay("2026-08-06T00:00", calendar: utc))
    }

    /// 매주·매년도 같다 — 주기와 무관하게 "목적지 = 마감".
    func testCompletion_weeklyAndYearly() {
        let w = changes(rec(due: "2026-08-05T08:00", unit: "weekly"), at: d(8, 5, 9))
        XCTAssertEqual(w[Recurrence.lastDoneDueKey], "2026-08-12T08:00")
        let y = changes(rec(due: "2026-08-05T08:00", unit: "yearly"), at: d(8, 5, 9))
        XCTAssertEqual(y[Recurrence.lastDoneDueKey], "2027-08-05T08:00")
    }

    // MARK: 안 적는 자리 (경계)

    /// 앵커(마감)가 없으면 전진할 게 없다 → 등식이 성립할 `due`가 없으므로 안 적는다.
    /// (`RecurrenceRecompleteTests.testNoAnchor_onlyLastDone`의 짝.)
    func testNoAnchor_fieldNotWritten() {
        let c = changes(rec(due: nil, resurface: "2026-08-05T07:00"), at: d(8, 5, 9))
        XCTAssertNotNil(c[Recurrence.lastDoneKey])
        XCTAssertNil(c[Recurrence.lastDoneDueKey])
    }

    /// 재완료 멱등(빈 변경)일 땐 아무것도 안 쓴다 — 빈 변경에 필드만 끼워 넣으면 (a)가 도로 열린다.
    func testAlreadyClosed_writesNothing() {
        let start = rec(due: "2026-08-05T08:00", resurface: "2026-08-05T07:00")
        var f = start.fields
        for (k, v) in changes(start, at: d(8, 5, 7, 30)) { f[k] = v }
        let after = ResolvedItem(id: "a", fields: f, deleted: false, confirmed: false, createdHLC: start.createdHLC)
        XCTAssertTrue(changes(after, at: d(8, 5, 7, 35)).isEmpty)
    }

    /// 비되풀이는 안 닿는다 — `status=done` 하나뿐.
    func testNonRecurrence_untouched() {
        let t = ResolvedItem(id: "t", fields: ["type": "info-action", "due": "2026-08-05", "raw": "일"],
                             deleted: false, confirmed: false, createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
        XCTAssertEqual(Recurrence.completionChanges(for: t, now: d(8, 5, 9), calendar: utc), ["status": "done"])
    }

    // MARK: 취소가 되돌린다 (InboxModel.undoRecurComplete의 Core 쪽 규약)

    /// 취소는 `priorValue`로 **직전 값**을 되돌린다 — 두 번 완료한 뒤 취소하면 첫 완료의 목적지로.
    /// (`undoRecurComplete`가 `due`·`resurface`·`lastDone`과 **같은 방식**으로 이 필드도 되돌린다.)
    func testUndo_restoresPriorDestination() {
        let events: [Event] = [
            .edit(id: "a", hlc: h(1, 0), [Recurrence.lastDoneDueKey: "2026-08-06T08:00"]),
            .edit(id: "a", hlc: h(2, 0), [Recurrence.lastDoneDueKey: "2026-08-07T08:00"]),
        ]
        XCTAssertEqual(Recurrence.priorValue(in: events, id: "a", key: Recurrence.lastDoneDueKey), "2026-08-06T08:00")
    }

    /// **첫 완료의 취소는 직전 값이 없다 → 지운다**(빈 값). 낡은 등식을 남기느니 옛 항목 폴백으로 내려보낸다.
    func testUndo_firstCompletion_clearsField() {
        let events: [Event] = [.edit(id: "a", hlc: h(1, 0), [Recurrence.lastDoneDueKey: "2026-08-06T08:00"])]
        XCTAssertNil(Recurrence.priorValue(in: events, id: "a", key: Recurrence.lastDoneDueKey),
                     "직전 값 없음 → InboxModel이 \"\"로 지운다")
    }

    // MARK: 병합 (새 필드 = 코드 추가 없이 필드별 LWW)

    /// 두 기기의 완료·catch-up이 엇갈리면 **등식이 깨져 under-claim 쪽으로 강등**된다 — 거짓 완료가 아니라.
    /// 이 파일에선 필드가 실제로 LWW로 병합된다는 것까지 고정한다(판정은 Stage 2).
    func testMerge_fieldIsLastWriterWins_andCanDivergeSafely() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0), date: "d", time: "t", source: "voice", raw: "약",
                    extra: ["type": "recurrence", "recur": "daily"]),
            .edit(id: "a", hlc: h(2, 0), ["due": "2026-08-06T08:00", Recurrence.lastDoneDueKey: "2026-08-06T08:00"]),
            .edit(id: "a", hlc: h(3, 0), ["due": "2026-08-07T08:00"]),   // 다른 기기의 catch-up 전진
        ])
        let it = r.live.first { $0.id == "a" }
        XCTAssertEqual(it?.due, "2026-08-07T08:00")
        XCTAssertEqual(it?.fields[Recurrence.lastDoneDueKey], "2026-08-06T08:00",
                       "완료 증인은 catch-up에 덮이지 않는다 → 등식이 깨져 안전한 쪽으로 강등된다")
    }
}
