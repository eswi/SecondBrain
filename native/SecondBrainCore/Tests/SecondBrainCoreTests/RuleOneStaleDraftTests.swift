import XCTest
@testable import SecondBrainCore

/// **규칙 1 — 검사한 쌍 ≠ 저장되는 쌍** (2026-08-06 조사, 2026-08-06 밤 재현).
///
/// 규칙 1은 **화면의 두 값**(마감·미리 알림)을 함께 보는 불변식인데, 저장은 `EditDiff`가 낸
/// **바뀐 한 값**만 내보내고 그것이 **현재 저장값** 위에 필드별 LWW로 얹힌다.
/// 그래서 화면이 낡아지는 경로가 하나라도 있으면 **적법한 쌍을 검사하고 위반인 쌍을 저장**한다.
///
/// 이 파일은 그 순서를 실제 항목 `가`의 값으로 재현한다(2026-08-06 00:45~00:57).
/// **다른 곳이 안 덮는 것:** 규칙 1 자체의 판정은 `RuleOneTests`·`RuleOneTimeTests`가 이미 덮는다
/// (그리고 그 판정은 **옳다** — 이 파일이 잡는 것은 판정이 아니라 **판정에 넘긴 입력**이다).
/// 완료·취소의 값 계산은 `RecurrenceRecompleteTests`·`RecurrenceLastDoneDueTests`가 덮는다.
///
/// ⚠️ 여기서 재현하는 것은 **App 층(`DetailView`)의 상태 흐름**이다 — Core 함수들을 실제 호출 순서로
/// 엮어 그 흐름을 모사한다. 모사한 자리는 각 단계에 코드 위치를 적어 둔다.
final class RuleOneStaleDraftTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func d(_ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: day, hour: h, minute: min))!
    }
    /// 되풀이 항목 하나(`가`와 같은 모양 — 매일·자동완성 없음).
    private func rec(due: String, resurface: String) -> ResolvedItem {
        ResolvedItem(id: "ga",
                     fields: ["type": "recurrence", "recur": "daily", "due": due,
                              "resurface": resurface, "raw": "가 - 이른 완료 시험"],
                     deleted: false, confirmed: true,
                     createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }
    /// 이벤트 반영 = 필드별 LWW 한 번. **앱이 쓰는 것과 같은 함수**(`ResolvedItem.applying`)를 탄다 —
    /// 재현이 실제 코드 경로를 지나게 해서 "테스트만 그렇게 계산한다"는 여지를 없앤다.
    private func apply(_ it: ResolvedItem, _ changes: [String: String]) -> ResolvedItem {
        it.applying(changes)
    }
    /// `InboxModel.undoRecurComplete`의 되돌림 — 완료가 바꾼 넷을 직전 값으로.
    /// (모델은 `Recurrence.priorValue(in: allEvents…)`로 직전 값을 찾는다. 여기선 직접 넘긴다.)
    private func undo(_ it: ResolvedItem, priorDue: String, priorResurface: String) -> ResolvedItem {
        apply(it, ["due": priorDue, "resurface": priorResurface,
                   Recurrence.lastDoneKey: "", Recurrence.lastDoneDueKey: ""])
    }

    // MARK: ★ 재현 — 위반이 저장된다

    /// **항목 `가`에서 실제로 일어난 순서.** 각 단계가 혼자서는 다 정당한데 합치면 위반이 저장된다.
    ///
    /// 마지막 단정이 **지금 실패한다** — 그것이 이 파일의 존재 이유다.
    /// (안 고쳤다면 실패하는 시험을 먼저 세우지 않으면, 통과가 무엇을 증명하는지 알 수 없다.)
    func testStaleDraft_partialSave_storesRule1Violation() {
        let now = d(8, 6, 0, 57)

        // ① 만든 그대로 — 마감 08-06 13:00 · 미리 알림 08-06 12:03. 둘 다 미래이고 **적법**하다.
        let created = rec(due: "2026-08-06T13:00", resurface: "2026-08-06T12:03")
        XCTAssertFalse(ItemSchedule.violatesRule1(resurface: created.resurface, due: created.due,
                                                  now: now, calendar: utc),
                       "전제: 만든 시점의 쌍은 적법하다")

        // ② **이른 완료**(F-1 ① 절차) — 마감·미리 알림이 함께 하루 전진한다(lead 보존).
        let completed = apply(created, Recurrence.completionChanges(for: created, now: now, calendar: utc))
        XCTAssertEqual(completed.due, "2026-08-07T13:00")
        XCTAssertEqual(completed.resurface, "2026-08-07T12:03")

        // ③ **상세를 닫고 다시 연다** — 화면은 이 시점의 값을 스냅숏으로 든다.
        //    `DetailView.item`(let, 스냅숏) + init의 `_due`/`_resurface` draft.
        let snapshot = completed
        let draftDue = snapshot.due          // 취소해도 안 바뀐다 — 그게 이 재현의 핵심이다
        var draftResurface = snapshot.resurface

        // ④ **[취소]** — 모델은 완료 전으로 돌아간다. 그런데 화면은 안 따라간다:
        //    `DetailView:533`의 취소는 `cycleDoneLocal`만 뒤집는다(draft는 그대로).
        let stored = undo(completed, priorDue: "2026-08-06T13:00", priorResurface: "2026-08-06T12:03")
        XCTAssertEqual(stored.due, "2026-08-06T13:00", "저장된 마감은 되돌아갔다")
        XCTAssertEqual(draftDue, "2026-08-07T13:00", "★ 화면의 마감은 낡은 채로 남는다 — 여기가 원인이다")

        // ⑤ 그 화면에서 **미리 알림 시각만** 손으로 고친다(12:03 → 12:00).
        draftResurface = "2026-08-07T12:00"

        // ⑥ 저장 검사(`DetailView.commit()` — 지금 코드)는 **화면 draft 쌍**을 본다 → 적법하다고 판정한다.
        //    **규칙 1은 제 일을 정확히 했다.** 08-07 12:00 ≤ 08-07 13:00 이므로 진짜로 적법하다.
        XCTAssertFalse(ItemSchedule.violatesRule1(resurface: draftResurface, due: draftDue,
                                                  now: now, calendar: utc),
                       "검사한 쌍(미리 알림 08-07 12:00 / 마감 08-07 13:00)은 적법하다")

        // ⑦ 그런데 저장되는 것은 **바뀐 필드 하나**다 — `EditDiff`는 스냅숏과 비교하므로
        //    마감은 "안 바뀐 것"으로 보여 이벤트에 안 실린다.
        let changes = EditDiff.changes(type: snapshot.type, due: draftDue,
                                       resurface: draftResurface, raw: snapshot.raw, from: snapshot)
        XCTAssertEqual(changes, ["resurface": "2026-08-07T12:00"],
                       "마감은 저장에 안 실린다 — 검사한 쌍의 절반만 나간다")

        // ⑧ 그 한 줄이 **취소 뒤의 실제 마감** 위에 LWW로 얹히면 최종 쌍은 이렇게 된다.
        let saved = apply(stored, changes)
        XCTAssertEqual(saved.due, "2026-08-06T13:00")
        XCTAssertEqual(saved.resurface, "2026-08-07T12:00")
        // **사실 기록** — 이 쌍은 위반이다. `가`에 지금 저장돼 있는 값이 정확히 이것이다.
        // (2026-08-06 밤 단계 0에서 이 자리의 `XCTAssertFalse`가 실패하는 것을 확인해 진단을 못박았다.)
        XCTAssertTrue(ItemSchedule.violatesRule1(resurface: saved.resurface, due: saved.due,
                                                 now: now, calendar: utc),
                      "저장되면 위반이 된다 — 아래 검사가 이것을 막아야 하는 이유")

        // ★ **불변식 — 저장 검사는 최종 쌍을 보고 이 저장을 막아야 한다.**
        //    입력은 화면 draft가 아니라 **현재 저장 상태(`stored`) + 이번 변경(`changes`)**이다.
        XCTAssertTrue(ItemSchedule.violatesRule1(applying: changes, to: stored, now: now, calendar: utc),
                      "★ 최종 쌍으로 검사하면 막힌다 — 검사한 쌍 = 저장되는 쌍")
    }

    /// **피해 — 항목이 자기 마감을 지날 때까지 숨는다.** 규칙 1이 막으려던 목적 그대로가 깨진다.
    /// 되풀이 게시 게이트는 미리 알림만 보므로(`ItemSchedule.isPublished` 1절) 회차가 마감보다 늦게 열린다.
    /// 위 재현이 만든 값을 그대로 쓴다 — **위반이 저장된다는 것만으로 끝나는 문제가 아니라는 근거.**
    func testStoredViolation_hidesItemPastItsOwnDeadline() {
        let broken = rec(due: "2026-08-06T13:00", resurface: "2026-08-07T12:00")
        XCTAssertTrue(ItemSchedule.violatesRule1(resurface: broken.resurface, due: broken.due,
                                                 now: d(8, 6, 1), calendar: utc),
                      "전제: 이 쌍은 위반이다")
        XCTAssertFalse(ItemSchedule.isPublished(broken, now: d(8, 6, 13, 1), calendar: utc),
                       "★ 마감(13:00)이 지났는데도 게시가 안 된다 — 자기 마감을 지날 때까지 숨는다")
        XCTAssertTrue(ItemSchedule.isPublished(broken, now: d(8, 7, 12, 1), calendar: utc),
                      "게시는 미리 알림(다음 날 12:00)에 가서야 열린다")
    }

    // MARK: 대조군 — 화면이 안 낡았으면 막힌다

    /// **같은 손편집이 낡지 않은 화면에서는 저장 단계에 닿지도 않는다.**
    /// 취소를 안 했으면(=화면과 저장값이 같으면) draft 쌍 = 최종 쌍이므로 지금 검사만으로 이미 막힌다.
    /// → 구멍의 원인이 **손편집 경로의 부재도, 되풀이 특례도 아니라 낡음**이라는 대조군.
    func testFreshDraft_sameEdit_isAlreadyBlockedToday() {
        let now = d(8, 6, 0, 57)
        let fresh = rec(due: "2026-08-06T13:00", resurface: "2026-08-06T12:03")
        // 낡음 없이 같은 값(다음 날 12:00)을 미리 알림에 넣으려 하면
        XCTAssertTrue(ItemSchedule.violatesRule1(resurface: "2026-08-07T12:00", due: fresh.due,
                                                 now: now, calendar: utc),
                      "화면이 저장값과 같으면 지금 검사가 이미 막는다 — 규칙 1에 구멍이 없다는 뜻")
    }

    // MARK: ★★ 회귀선 1 — 적법한 저장은 그대로 저장된다 (과잉 차단 금지)
    //
    // **이 절이 이 변경에서 가장 위험한 자리다.** 검사를 최종 쌍으로 옮기면 "안 바뀐 필드"가
    // 검사에 새로 들어오므로, 잘못 짜면 **여태 되던 정상 저장이 막힌다.** 아래가 그 그물이다.

    /// 미리 알림만 바꾸는 부분 저장 — 최종 쌍이 적법하면 **통과해야** 한다.
    func testPartialSave_legalFinalPair_passes() {
        let now = d(8, 6, 0, 57)
        let it = rec(due: "2026-08-10T13:00", resurface: "2026-08-06T12:00")
        XCTAssertFalse(ItemSchedule.violatesRule1(applying: ["resurface": "2026-08-09T12:00"],
                                                  to: it, now: now, calendar: utc),
                       "마감(08-10)보다 앞이면 통과한다")
    }

    /// 마감만 바꾸는 부분 저장 — **안 바뀐 미리 알림**과 겹쳐도 적법하면 통과.
    func testPartialSave_dueOnly_usesStoredResurface() {
        let now = d(8, 6, 0, 57)
        let it = rec(due: "2026-08-07T13:00", resurface: "2026-08-07T12:00")
        XCTAssertFalse(ItemSchedule.violatesRule1(applying: ["due": "2026-08-20T13:00"],
                                                  to: it, now: now, calendar: utc),
                       "마감을 미래로 미루는 것은 항상 적법하다")
        // 반대로 마감을 **미리 알림보다 앞으로 당기면** 역전된다 — 이쪽은 막혀야 한다.
        XCTAssertTrue(ItemSchedule.violatesRule1(applying: ["due": "2026-08-06T13:00"],
                                                 to: it, now: now, calendar: utc),
                      "마감을 당겨 역전시키는 경로도 같은 검사로 잡힌다(조사 때 지목된 경우)")
    }

    /// 시점과 무관한 저장(본문·분류·주기만) — 시점 필드가 changes에 없으면 **저장값 그대로** 판정.
    /// 이미 어긋난 항목(=`가`)에서도 본문 수정이 막히면 안 된다… 는 아니다: 저장값이 이미 위반이면
    /// **막힌다.** 그 대가를 여기 명시해 둔다(고치는 편집은 시점 필드를 담으므로 통과한다).
    func testNonScheduleSave_inheritsStoredPair() {
        let now = d(8, 6, 0, 57)
        let ok = rec(due: "2026-08-10T13:00", resurface: "2026-08-09T12:00")
        XCTAssertFalse(ItemSchedule.violatesRule1(applying: ["raw": "고친 본문"],
                                                  to: ok, now: now, calendar: utc),
                       "적법한 항목의 본문 수정은 통과")
        let broken = rec(due: "2026-08-07T13:00", resurface: "2026-08-08T12:00")   // `가`의 현재 값
        XCTAssertTrue(ItemSchedule.violatesRule1(applying: ["raw": "고친 본문"],
                                                 to: broken, now: now, calendar: utc),
                      "이미 어긋난 항목은 본문만 고쳐도 막힌다 — 승인된 대가(고치려면 시점을 함께 고친다)")
        XCTAssertFalse(ItemSchedule.violatesRule1(applying: ["resurface": "2026-08-07T12:00"],
                                                  to: broken, now: now, calendar: utc),
                       "★ 고치는 편집은 통과한다 — 어긋난 항목이 영구히 잠기지 않는다")
    }

    // MARK: 회귀선 2·3 — 원래 제약 없는 자리는 그대로 (기존 규칙 불변)

    /// 마감 없음 / 마감 지남 → 제약 없음. 비우기(`"none"`·`""`)도 시점 없음으로 처리된다.
    func testNoOrPastDue_stillUnconstrained() {
        let now = d(8, 6, 12)
        let noDue = ResolvedItem(id: "n", fields: ["type": "recurrence", "recur": "daily",
                                                  "resurface": "2026-08-09T12:00", "raw": "약"],
                                 deleted: false, confirmed: true,
                                 createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
        XCTAssertFalse(ItemSchedule.violatesRule1(applying: [:], to: noDue, now: now, calendar: utc),
                       "마감이 없으면 제약 없음")
        let past = rec(due: "2026-08-01T13:00", resurface: "2026-08-01T12:00")
        XCTAssertFalse(ItemSchedule.violatesRule1(applying: ["resurface": "2026-08-20T12:00"],
                                                  to: past, now: now, calendar: utc),
                       "지난 마감은 미루기 제약이 없다(기존 규칙)")
        let cleared = rec(due: "2026-08-10T13:00", resurface: "2026-08-09T12:00")
        for empty in ["none", ""] {
            XCTAssertFalse(ItemSchedule.violatesRule1(applying: ["due": empty], to: cleared,
                                                      now: now, calendar: utc),
                           "마감을 비우면(\(empty.isEmpty ? "빈값" : empty)) 제약이 사라진다")
            XCTAssertFalse(ItemSchedule.violatesRule1(applying: ["resurface": empty], to: cleared,
                                                      now: now, calendar: utc),
                           "미리 알림을 비우면 위반할 것이 없다")
        }
    }

    /// **미리 알림 = 마감(정각)은 허용** — 실질 lead 0 규약(기존 `violatesRule1` 주석).
    /// 새 함수가 이 경계를 안 옮겼는지 본다.
    func testLeadEqualsDeadline_stillAllowed() {
        let now = d(8, 6, 0, 57)
        let it = rec(due: "2026-08-10T13:00", resurface: "2026-08-09T12:00")
        XCTAssertFalse(ItemSchedule.violatesRule1(applying: ["resurface": "2026-08-10T13:00"],
                                                  to: it, now: now, calendar: utc),
                       "정각 일치는 위반이 아니다")
        XCTAssertTrue(ItemSchedule.violatesRule1(applying: ["resurface": "2026-08-10T13:01"],
                                                 to: it, now: now, calendar: utc),
                      "1분만 넘어도 위반 — 경계가 그대로다")
    }

    // MARK: ★★ (b) — 완료·취소가 화면 draft도 같이 옮긴다 (`EditDiff.draftSync`)
    //
    // (a)가 저장을 지키고 (b)가 화면을 지킨다. **어느 하나만으로는 절반이다** —
    // (a)만 있으면 사람은 왜 막혔는지 모르는 팝업을 보고, (b)만 있으면 낡음의 다른 경로가 그대로 남는다.

    /// 낡음이 사라진다 — 취소가 되돌린 값이 draft에도 들어가므로, 그 위에서 한 손편집은 **적법한 쌍**이 된다.
    /// 위 `testStaleDraft_partialSave_storesRule1Violation`의 ④를 (b) 있는 코드로 다시 밟은 것.
    func testDraftSync_undoMovesTheScreen_soTheNextEditIsLegal() {
        let undoApplied = ["due": "2026-08-06T13:00", "resurface": "2026-08-06T12:03",
                           Recurrence.lastDoneKey: "", Recurrence.lastDoneDueKey: ""]
        let sync = EditDiff.draftSync(applied: undoApplied, touched: [])
        XCTAssertEqual(sync, ["due": "2026-08-06T13:00", "resurface": "2026-08-06T12:03"],
                       "시점 두 칸만 화면으로 되받는다(lastDone·lastDoneDue는 draft 칸이 아니다)")
        // 화면이 08-06 13:00을 들고 있으면 미리 알림을 08-07로 넣는 손편집은 애초에 위반으로 잡힌다.
        XCTAssertTrue(ItemSchedule.violatesRule1(resurface: "2026-08-07T12:00", due: sync["due"],
                                                 now: d(8, 6, 0, 57), calendar: utc),
                      "★ 화면이 안 낡았으면 그 손편집이 화면 단계에서 이미 막힌다 — `가`가 안 생긴다")
    }

    /// ★★ **회귀선 6 — 사람의 미저장 편집이 완료 때 지워지지 않는다.**
    ///
    /// **요구하지 않았는데 찾은 것이다.** (b)를 "완료·취소가 draft를 되돌린다"로만 짜면
    /// **마감을 고쳐 둔 채 완료를 누른 사람의 편집이 조용히 사라진다** — 고치려던 사고(낡음)를
    /// 다른 사고(편집 유실)로 바꾸는 것이라 (b)를 넣는 순간 같이 막아야 했다.
    /// **필드별로 갈린다:** 손댄 칸은 사람 값이 남고, 안 손댄 칸만 따라간다.
    func testDraftSync_neverOverwritesUnsavedEdit_perField() {
        let applied = ["due": "2026-08-07T13:00", "resurface": "2026-08-07T12:03",
                       Recurrence.lastDoneKey: "2026-08-06T00:57"]
        // 사람이 **마감만** 고쳐 뒀다 → 마감은 그대로 두고 미리 알림만 동기화한다.
        XCTAssertEqual(EditDiff.draftSync(applied: applied, touched: ["due"]),
                       ["resurface": "2026-08-07T12:03"],
                       "★ 마감은 사람 것이라 안 건드린다 — 미리 알림만 따라간다")
        // 반대쪽도 대칭이어야 한다(한쪽만 되면 그게 버그다).
        XCTAssertEqual(EditDiff.draftSync(applied: applied, touched: ["resurface"]),
                       ["due": "2026-08-07T13:00"],
                       "미리 알림이 사람 것이면 마감만 따라간다")
        // 둘 다 손댔으면 아무것도 안 건드린다.
        XCTAssertTrue(EditDiff.draftSync(applied: applied, touched: ["due", "resurface"]).isEmpty,
                      "둘 다 사람 것이면 화면을 하나도 안 옮긴다")
        // 본문·분류를 고쳐 둔 것은 시점 동기화를 막지 않는다(서로 다른 칸이다).
        XCTAssertEqual(EditDiff.draftSync(applied: applied, touched: ["raw", "type"]),
                       ["due": "2026-08-07T13:00", "resurface": "2026-08-07T12:03"],
                       "다른 칸의 편집은 시점 동기화와 무관하다")
    }

    /// `ResolvedItem.applying` — 빈 값은 지움, 제어 필드는 안 건드림. 위 재현과 앱의 기준선 갱신이 같이 쓴다.
    func testApplying_clearsOnEmpty_andKeepsControlFields() {
        let it = rec(due: "2026-08-06T13:00", resurface: "2026-08-06T12:03")
        let out = it.applying(["due": "2026-08-07T13:00", "resurface": "", "raw": "새 본문"])
        XCTAssertEqual(out.due, "2026-08-07T13:00")
        XCTAssertNil(out.resurface, "빈 값은 지움")
        XCTAssertEqual(out.raw, "새 본문")
        XCTAssertEqual(out.id, it.id)
        XCTAssertEqual(out.confirmed, it.confirmed, "confirmed는 편집으로 안 바뀐다(단방향)")
        XCTAssertEqual(out.deleted, it.deleted)
        XCTAssertEqual(out.createdHLC, it.createdHLC, "캡처 시점은 성역")
        XCTAssertEqual(it.applying([:]), it, "빈 변경은 항등")
    }

    /// 시점 아닌 칸은 **화면으로 되받지 않는다** — `lastDone`·`lastDoneDue`는 draft에 없는 값이다.
    /// 되받으면 그 값이 [저장]에 실려 완료 기록을 사람 편집인 것처럼 다시 쓰게 된다.
    func testDraftSync_onlyScheduleFields() {
        let applied = [Recurrence.lastDoneKey: "2026-08-06T00:57",
                       Recurrence.lastDoneDueKey: "2026-08-07T13:00",
                       "status": "done", "due": "2026-08-07T13:00"]
        XCTAssertEqual(EditDiff.draftSync(applied: applied, touched: []), ["due": "2026-08-07T13:00"])
    }

    /// 값 지움(`""`)도 그대로 전달된다 — 부르는 쪽이 "비움"으로 옮긴다.
    /// **키가 없는 것("안 움직였다")과 값이 빈 것("비웠다")을 섞지 않는다** — 취소는 직전 값이 없는 칸을
    /// dict에 안 담으므로, 키 유무가 그대로 뜻을 갖는다.
    func testDraftSync_emptyMeansClear_missingMeansUntouched() {
        XCTAssertEqual(EditDiff.draftSync(applied: ["resurface": ""], touched: []), ["resurface": ""])
        XCTAssertTrue(EditDiff.draftSync(applied: [Recurrence.lastDoneKey: ""], touched: []).isEmpty,
                      "취소가 lastDone만 지웠으면 화면 시점 칸은 안 움직인다")
    }

    /// **두 값을 함께 고치는 저장** — 최종 쌍이 적법하면 통과. 낡음 없이 정상적으로 둘을 옮기는 경우.
    func testBothFieldsChangedTogether_judgedAsOnePair() {
        let now = d(8, 6, 0, 57)
        let it = rec(due: "2026-08-07T13:00", resurface: "2026-08-07T12:00")
        XCTAssertFalse(ItemSchedule.violatesRule1(
            applying: ["due": "2026-08-20T13:00", "resurface": "2026-08-19T12:00"],
            to: it, now: now, calendar: utc), "함께 옮기면 통과")
        XCTAssertTrue(ItemSchedule.violatesRule1(
            applying: ["due": "2026-08-20T13:00", "resurface": "2026-08-21T12:00"],
            to: it, now: now, calendar: utc), "함께 옮겨도 역전이면 막힌다")
    }
}
