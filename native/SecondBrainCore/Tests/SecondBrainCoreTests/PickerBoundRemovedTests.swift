import XCTest
@testable import SecondBrainCore

/// **B(2026-08-08) — 고르는 단계의 상한을 뺐다. 막는 곳은 [저장] 하나다.**
///
/// ⚠️ **이 파일은 단계 0이 아니다 — 회귀 방지용이다.**
/// B가 바꾼 것은 화면(`DetailView`의 `DatePicker`에서 `in: ...ub` 제거)이고 **판정 로직은 안 바꿨다.**
/// 그래서 여기 시험은 **고치기 전에도 전부 통과한다.** 그걸 "고쳐졌다는 증거"로 읽으면 거짓 안심이다.
/// B의 판정선은 실기기 확인표다(`docs/native/date-roles-verify-checklist.md` B-5-B ①②③).
///
/// **그럼 왜 쓰나:** B 이후 **사람이 위반을 고르는 것이 정상 경로**가 된다. 지금까지는 피커가 막아
/// 도달이 드물던 자리에 이제 실제로 값이 들어온다. 그 경계가 흔들리면 조용히 저장되므로 못박아 둔다.
///
/// 특히 `testSilentlyChangedValuePasses`가 **오늘 조용히 저장될 뻔한 값**이다 — 규칙 1 위반이 아니라서
/// 저장 검사가 못 잡는다. 그것이 B를 택한 이유다(막는 것으로는 못 막고, 안 바꾸는 것으로 막는다).
final class PickerBoundRemovedTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    /// 2026-08-07 22:00 — 재현 당시(마감 08-09는 미래라 규칙이 깨어 있다).
    private var night: Date { utc.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 22))! }

    private func v(_ resurface: String?, _ due: String?) -> Bool {
        ItemSchedule.violatesRule1(resurface: resurface, due: due, now: night, calendar: utc)
    }
    private func bound(_ due: String?, hasTime: Bool) -> String? {
        ItemSchedule.resurfaceUpperBound(due: due, now: night, resurfaceHasTime: hasTime, calendar: utc)
            .map { ItemSchedule.dayString($0, calendar: utc) }
    }

    // MARK: 저장 검사가 옛 피커 상한을 **덮는가** (같은 경계 + 더 넓게)

    /// 시각 없는 미리 알림 — 옛 상한(마감−1일)과 저장 검사의 경계가 **같은 날에서** 갈린다.
    func testDateOnly_saveCheckMatchesOldPickerBound() {
        XCTAssertEqual(bound("2026-08-09T19:00", hasTime: false), "2026-08-08")   // 옛 피커가 열어두던 마지막 날
        XCTAssertFalse(v("2026-08-08", "2026-08-09T19:00"))                       // 그 날까지 = 통과
        XCTAssertTrue(v("2026-08-09", "2026-08-09T19:00"))                        // 그 다음날부터 = 막힘
    }

    /// 시각 있는 미리 알림 — 옛 상한(마감 당일)과 저장 검사의 **날짜** 경계가 같다.
    func testTimed_saveCheckMatchesOldPickerBound() {
        XCTAssertEqual(bound("2026-08-09T19:00", hasTime: true), "2026-08-09")    // 옛 피커: 마감 당일까지
        XCTAssertFalse(v("2026-08-09T09:00", "2026-08-09T19:00"))                 // 같은 날 이른 시각 = 통과
        XCTAssertTrue(v("2026-08-10T09:00", "2026-08-09T19:00"))                  // 그 다음날 = 막힘
    }

    /// **★ 피커가 못 잡던 것을 저장 검사는 잡는다** — 같은 날 **늦은 시각**.
    /// 피커 상한은 날짜만 봤고 시각 칸엔 애초에 상한이 없었다(반쪽 방어). B는 방어를 줄인 게 아니다.
    func testTimed_sameDayLaterThanDue_pickerMissedItSaveCatchesIt() {
        XCTAssertEqual(bound("2026-08-09T19:00", hasTime: true), "2026-08-09")    // 피커는 08-09를 허용했다
        XCTAssertTrue(v("2026-08-09T21:00", "2026-08-09T19:00"))                  // 그런데 21:00은 위반이다
    }

    /// 마감이 없거나 지났으면 양쪽 다 제약 없음 — B 전후로 안 달라진다.
    func testNoDueOrPastDue_unconstrainedBothWays() {
        XCTAssertNil(bound(nil, hasTime: false))
        XCTAssertNil(bound("2026-08-01T19:00", hasTime: false))                   // 지난 마감
        XCTAssertFalse(v("2026-12-31", nil))
        XCTAssertFalse(v("2026-12-31", "2026-08-01T19:00"))
    }

    // MARK: 오늘 조용히 바뀐 값 그 자체

    /// **2026-08-07 밤에 앱이 스스로 만든 값.** 마감 08-09 19:00 draft에서 미리 알림 08-08의
    /// 시각 토글을 켜자 날짜가 08-09로 밀렸다 → `2026-08-09T09:00`.
    ///
    /// ★ **이 값은 규칙 1 위반이 아니다** — 09:00 ≤ 19:00. 저장 검사를 **그냥 통과한다.**
    /// 사람이 안 건드린 값이 조용히 바뀌고 조용히 저장된다는 뜻이다.
    /// 여기서 배울 것: **막는 것으로는 이 종류를 못 막는다.** 안 바꾸는 것으로만 막힌다(= B).
    ///
    /// ⚠️ **이건 가정이 아니다 — 실데이터로 증명됐다(2026-08-08).**
    /// `가`(AF9BAB30)의 이벤트 로그에 **그 값이 그대로 들어가 있다**:
    /// `@ 1786146166495 | AF9BAB30 | set due=2026-08-09T19:00 resurface=2026-08-09T09:00` (08:42:46).
    /// ①②③을 재보는 사이 [저장]이 눌렸고 **여기 적힌 대로 아무 저항 없이 통과했다.**
    /// 그리고 그 저장이 **(c)의 실물 증거(`가`의 뒤집힌 lead)를 덮어 지웠다** — 다른 미결의 증거가
    /// 이 버그에 지워진 것이라, 조용한 변경이 무엇을 앗아가는지의 실례이기도 하다.
    func testSilentlyChangedValuePasses() {
        XCTAssertFalse(v("2026-08-09T09:00", "2026-08-09T19:00"),
                       "조용히 바뀐 값이 위반이었다면 저장 검사가 잡았을 것이다. 안 잡힌다 — 그래서 B다.")
        XCTAssertNil(ItemSchedule.rule1Block(applying: ["resurface": "2026-08-09T09:00"],
                                             to: item(due: "2026-08-09T19:00", resurface: "2026-08-08"),
                                             now: night, calendar: utc),
                     "막을 이유가 없으므로 안내 문구도 안 뜬다.")
    }

    /// 토글을 **되돌렸을 때** 나오던 값(①) — 이쪽은 위반이라 저장에서 막힌다.
    /// 같은 조용한 변경인데 **한쪽만 잡힌다**는 것이 "저장 검사로는 부족하다"의 증거다.
    func testToggledBackValueIsBlocked() {
        XCTAssertTrue(v("2026-08-09", "2026-08-09T19:00"))
        guard case .dayBeforeDeadline(let cap, let deadline)? =
                ItemSchedule.rule1Block(applying: ["resurface": "2026-08-09"],
                                        to: item(due: "2026-08-09T19:00", resurface: "2026-08-08"),
                                        now: night, calendar: utc) else {
            return XCTFail("시각 없는 미리 알림이 마감과 같은 날 → dayBeforeDeadline이어야 한다")
        }
        XCTAssertEqual(cap, "2026-08-08")
        XCTAssertEqual(deadline, "2026-08-09T19:00")
    }

    // MARK: 미루기는 B에 안 딸려간다

    /// `deferSevenDays`는 `resurfaceUpperBound`를 **내부에서** 쓴다 — 피커의 `in:`과 무관하다.
    /// B 이후에도 상한까지 당기고, 당겼으면 화면이 알린다(조용하지 않다 = 원칙에 안 어긋난다).
    func testDeferStillCapsAtUpperBound() {
        XCTAssertEqual(ItemSchedule.deferSevenDays(due: "2026-08-09T19:00", now: night,
                                                   resurfaceHasTime: false, calendar: utc),
                       .deferred(to: "2026-08-08", capped: true))
    }

    private func item(due: String, resurface: String) -> ResolvedItem {
        ResolvedItem(id: "B-TEST", fields: ["type": "task", "raw": "상한 제거 시험",
                                            "due": due, "resurface": resurface],
                     deleted: false, confirmed: true,
                     createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }
}
