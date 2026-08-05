import XCTest
@testable import SecondBrainCore

/// **Stage 0 그물 — (b) 착수 전 계측에서 나온 구멍 두 개를 못박는다** (2026-08-05 저녁, 맥미니).
///
/// (b)("닫은 회차를 기록") 방향을 정한 뒤, 계획을 적기 전에 후보 판정을 코드로 재보다가
/// **어제 문서가 "없다"고 정리한 문제 두 개가 아직 열려 있는 것**을 발견했다. 판단 근거가 바뀌었으므로
/// 고치기 전에 여기 먼저 박는다.
///
/// **이 파일의 두 `testHole_*`은 옳은 기대를 적고 지금은 실패한다.** `XCTExpectFailure`로 감싸
/// 스위트는 초록을 유지하되 **실패 사실 자체를 기록**한다. Stage 2에서 판정이 바뀌면 감싼 것을
/// **지우기만** 하면 통과한다 — 그 diff가 "고치기 전에 무엇이었나"의 기록이다.
///
/// 5-A의 `_현재동작` 방식(버그를 사실로 단정 → 다음 커밋에서 뒤집기)과 목적은 같다. 이번엔 반대로
/// 적은 이유: 이 둘은 **어제 "해소됐다"고 적힌 문제**라, 버그 쪽을 단정으로 적으면 그 오정리를
/// 코드에 한 번 더 못박게 된다. 옳은 기대 + 표시된 실패가 더 정직하다.
///
/// 아래 `testNet_*`은 **Stage 2 뒤에도 그대로여야 하는 것**(회귀 감지선)이다.
final class RecurrenceHolesTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func d(_ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: day, hour: h, minute: min))!
    }
    private func rec(due: String, resurface: String? = nil, lastDone: String? = nil,
                     unit: String = "daily", auto: String? = nil) -> ResolvedItem {
        var f: [String: String] = ["type": "recurrence", "recur": unit, "due": due, "raw": "약"]
        if let resurface { f["resurface"] = resurface }
        if let lastDone { f[Recurrence.lastDoneKey] = lastDone }
        if let auto { f[Recurrence.autoKey] = auto }
        return ResolvedItem(id: "a", fields: f, deleted: false, confirmed: false,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }
    /// 이벤트를 실제로 반영한 다음 상태. 빈 문자열 = 값 지움(앱의 `set k=` 규약).
    private func apply(_ it: ResolvedItem, _ changes: [String: String]) -> ResolvedItem {
        var f = it.fields
        for (k, v) in changes { if v.isEmpty { f.removeValue(forKey: k) } else { f[k] = v } }
        return ResolvedItem(id: it.id, fields: f, deleted: it.deleted,
                            confirmed: it.confirmed, createdHLC: it.createdHLC)
    }
    private func press(_ it: ResolvedItem, at now: Date) -> (next: ResolvedItem, changes: [String: String]) {
        let c = Recurrence.completionChanges(for: it, now: now, calendar: utc)
        return (apply(it, c), c)
    }

    // MARK: - 구멍 1 — (a) 가드가 회차 시각을 지나면 풀린다

    /// **어제 "(a) 고쳤으니 데이터 유실은 없다"고 정리한 것이 틀렸다.**
    ///
    /// `alreadyClosedThisCycle`의 2절은 `now ≤ 방금 닫은 회차`를 요구한다 → **그 시각이 지나면 가드가 풀린다.**
    /// 계측(2026-08-05 저녁, 이른 완료 08-05 07:30 → 마감 08-06):
    /// ```
    ///   08-05 07:35  막힘 ✓        08-05 09:00  통과 → 마감 08-07 ✗
    ///   08-05 08:01  통과 → 08-07 ✗   08-05 23:00  통과 → 마감 08-07 ✗
    /// ```
    /// 즉 **막은 것은 회차 시각 이전의 재압뿐**이고, 8시가 지나면 08-06 회차가 그대로 사라진다 —
    /// 내일 약이 목록·알림 양쪽에서 없어지는 그 경로가 **아직 열려 있었다.**
    ///
    /// 아이러니: §5-B가 후보 ①(가드형)의 단점으로 지적한 *"시간이 지나면 다시 벌어진다"* 가
    /// **(a)의 가드 자체에 있었다.** → 정본 §5-A·§5-B의 "데이터 유실은 이미 없다"는 정정 대상.
    func testHole1_recompleteAfterAnchorStillEatsACycle() {
        let start = rec(due: "2026-08-05T08:00", resurface: "2026-08-05T07:00")
        let first = press(start, at: d(8, 5, 7, 30))                  // 이른 완료
        XCTAssertEqual(first.next.due, "2026-08-06T08:00", "전제: 첫 완료로 한 회차 전진")
        XCTAssertTrue(press(first.next, at: d(8, 5, 7, 35)).changes.isEmpty,
                      "대조군 — 회차 시각 **전**의 재압은 (a) 가드가 실제로 막는다")

        // ↓ 옳은 기대. 지금은 실패한다(마감이 08-07로 또 밀린다).
        XCTExpectFailure("구멍 1 — Stage 2에서 판정이 바뀌면 이 감쌈을 지운다") {
            let again = press(first.next, at: d(8, 5, 9))             // 회차 시각을 지난 뒤 재압
            XCTAssertTrue(again.changes.isEmpty, "이미 닫은 회차의 재압은 회차 시각 뒤에도 빈 변경이어야 한다")
            XCTAssertEqual(again.next.due, "2026-08-06T08:00", "08-06 회차가 사라지면 안 된다")
        }
    }

    // MARK: - 구멍 2 — lead 창의 거짓 완료

    /// **"안 했는데 완료로 보인다" — 지금까지의 문제와 방향이 반대다.**
    ///
    /// under-claim(안 뜸)은 사람이 다시 누르면 되지만, **거짓 완료는 약을 안 먹고 넘어가게 만든다.**
    /// 그래서 우선순위가 더 높다.
    ///
    /// 계측(정시 완료 08-04 08:05 → 마감 08-05 08:00 · 미리 알림 08-05 07:00):
    /// ```
    ///   08-04 20:00  게시 false  칩 "완료"  ✓
    ///   08-05 07:30  게시 TRUE   칩 "완료"  ✗  ← '지금 챙길 것'에 있는데 "완료"
    ///   08-05 09:00  게시 true   칩 없음    ✓
    /// ```
    /// **§5-B의 "게이트와 갈릴 수 없다"는 lead가 있으면 틀리다.** 게이트(`isPublished`)는 `resurface`를,
    /// 판정(`doneThisCycle`)은 `due`를 본다 — lead 창(07:00~08:00) 동안 둘은 **다른 사실**이다.
    /// 2026-08-03 #4(칩과 게이트가 갈림)가 lead 창에서 살아 있었던 셈이고, 이번엔 방향이 거짓 완료 쪽이다.
    /// 덤: 칩이 **마감 시각에 스스로 꺼지는 것**(§5-B가 ①(가드형)의 단점이라 적은 만료)도 이미 여기 있다.
    func testHole2_leadWindowShowsFalseComplete() {
        let start = rec(due: "2026-08-04T08:00", resurface: "2026-08-04T07:00")
        let after = press(start, at: d(8, 4, 8, 5)).next               // 정시 완료 → 다음 회차로
        XCTAssertEqual(after.due, "2026-08-05T08:00")
        XCTAssertEqual(after.resurface, "2026-08-05T07:00")

        let inLead = d(8, 5, 7, 30)                                    // 오늘 약을 아직 안 먹은 시각
        XCTAssertTrue(ItemSchedule.isPublished(after, now: inLead, calendar: utc),
                      "대조군 — 이 시각 이 항목은 '지금 챙길 것'에 있다(게시됨)")

        // ↓ 옳은 기대. 지금은 실패한다(게시된 채로 "완료"라고 말한다).
        XCTExpectFailure("구멍 2 — Stage 2에서 게이트 절이 들어오면 이 감쌈을 지운다") {
            XCTAssertFalse(Recurrence.doneThisCycle(after, now: inLead, calendar: utc),
                           "게시된(= 이번 회차가 열린) 항목을 '완료'라 하면 안 된다 — 거짓 완료")
        }
    }

    // MARK: - 그물 (Stage 2 뒤에도 그대로여야 하는 것)

    /// lead 창 **밖**에서는 완료 표시가 유지된다 — 구멍 2를 고치면서 이쪽까지 꺼버리면
    /// under-claim을 다른 형태로 되살리는 것이다(§5-B가 ①(가드형)의 "만료"라 부른 그것).
    func testNet_completeStaysOutsideLeadWindow() {
        let after = press(rec(due: "2026-08-04T08:00", resurface: "2026-08-04T07:00"), at: d(8, 4, 8, 5)).next
        for now in [d(8, 4, 8, 6), d(8, 4, 20), d(8, 5, 6, 30)] {
            XCTAssertFalse(ItemSchedule.isPublished(after, now: now, calendar: utc), "아직 회차가 안 열렸다")
            XCTAssertTrue(Recurrence.doneThisCycle(after, now: now, calendar: utc),
                          "완료 표시는 다음 회차가 열릴 때까지 유지되어야 한다")
        }
    }

    /// **넘어감(catch-up 자동 전진)은 완료가 아니다** — witness 원칙의 결과. §5-B 표의 B 상태.
    /// 이 단정은 (b) 전후로 **값이 같아야** 한다(지금은 `lastDone` 비교로, Stage 2 뒤엔 새 필드 등식으로).
    func testNet_catchUpAdvanceIsNotComplete() {
        let start = rec(due: "2026-08-04T08:00", resurface: "2026-08-04T07:00", auto: "noon")
        let done = press(start, at: d(8, 4, 9)).next                   // 08-04 완료 → 마감 08-05
        XCTAssertEqual(done.due, "2026-08-05T08:00")

        let now = d(8, 5, 12, 30)                                      // 08-05 정오 지남 → catch-up
        guard let cu = Recurrence.catchUpChanges(done, now: now, calendar: utc) else {
            return XCTFail("전제: 정오 임계가 지나 catch-up이 일어나야 한다")
        }
        let skipped = apply(done, cu)
        XCTAssertEqual(skipped.due, "2026-08-06T08:00", "넘어감 — 08-05 회차를 안 하고 지나갔다")
        XCTAssertFalse(Recurrence.doneThisCycle(skipped, now: now, calendar: utc),
                       "자동으로 넘어간 회차를 '완료'라 하면 앱이 거짓말이 된다")
        XCTAssertEqual(Recurrence.missed(skipped, now: now, calendar: utc), 0,
                       "넘어간 회차는 놓침으로도 안 잡힌다(§4 '자동완성이 있으면 안 쌓인다')")
    }

    /// ★ **witness 원칙을 문장이 아니라 구조로 고정한다.**
    /// catch-up·켜기 보정은 **회차 칸만** 옮긴다 — 완료 증인 필드는 절대 안 건드린다.
    /// 그게 "완료"와 "넘어감"을 가르는 유일한 정보이므로, 여기 키가 하나라도 새면 (b) 전체가 무너진다.
    /// Stage 1에서 새 필드가 들어와도 **이 테스트가 자동으로 잡는다**(허용 키 집합이 닫혀 있다).
    func testNet_catchUpAndResumeNeverWriteCompletionFields() {
        let allowed: Set<String> = ["due", "resurface", Recurrence.pausedAtKey]

        // catch-up
        let auto = rec(due: "2026-08-01T08:00", resurface: "2026-08-01T07:00", auto: "endOfDay")
        guard let cu = Recurrence.catchUpChanges(auto, now: d(8, 5, 9), calendar: utc) else {
            return XCTFail("전제: 자동완성 항목이 며칠 밀렸으면 catch-up이 있어야 한다")
        }
        XCTAssertTrue(Set(cu.keys).isSubset(of: allowed), "catch-up이 쓴 키: \(Set(cu.keys))")

        // 켜기 보정(resume)
        var f = rec(due: "2026-08-01T08:00", resurface: "2026-08-01T07:00").fields
        f[Recurrence.pausedAtKey] = "2026-08-02T00:00"                 // 꺼뒀다가 켠 상태(paused 없음)
        let resumed = ResolvedItem(id: "a", fields: f, deleted: false, confirmed: false,
                                   createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
        guard let rc = Recurrence.resumeChanges(resumed, now: d(8, 5, 9), calendar: utc) else {
            return XCTFail("전제: 꺼둔 기록이 있으면 켤 때 보정이 있어야 한다")
        }
        XCTAssertTrue(Set(rc.keys).isSubset(of: allowed), "resume이 쓴 키: \(Set(rc.keys))")
    }

    /// **옛 항목 폴백의 기준선** — 새 필드가 없는 항목(= 이 변경 전에 만들어진 모든 되풀이)의 판정은
    /// Stage 2 뒤에도 **지금과 똑같아야** 한다. 마이그레이션을 안 하기로 했으므로 이게 안전의 근거다.
    /// (세 모양 = §5-B 표의 "했다 / 아직 / 넘어갔다".)
    func testNet_oldItemsWithoutNewFieldKeepTodaysVerdict() {
        let now = d(8, 2, 12)
        let cases: [(String, ResolvedItem, Bool)] = [
            ("했다",     rec(due: "2026-08-03T08:00", lastDone: "2026-08-02T08:00"), true),
            ("아직",     rec(due: "2026-08-02T08:00", lastDone: "2026-08-02T08:00"), false),
            ("넘어갔다", rec(due: "2026-08-03T08:00", lastDone: "2026-08-01T08:00", auto: "endOfDay"), false),
        ]
        for (name, it, expected) in cases {
            XCTAssertNil(it.fields["lastDoneDue"], "\(name): 전제 — 옛 항목엔 새 필드가 없다")
            XCTAssertEqual(Recurrence.doneThisCycle(it, now: now, calendar: utc), expected, name)
        }
    }
}
