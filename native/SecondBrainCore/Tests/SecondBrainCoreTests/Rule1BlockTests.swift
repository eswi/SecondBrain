import XCTest
@testable import SecondBrainCore

/// **규칙 1이 막은 이유를 가른다 — 미결 3번** (2026-08-07).
///
/// 규칙 1은 2026-08-03에 **시각 인지**로 갈렸는데 **화면 문구는 하나로 남았다.**
/// 그 결과 시각 위반일 때 문장이 ⓐ 자기모순이고(「마감 **하루 전**(**마감 당일**)까지만」)
/// ⓑ **원인은 시각인데 날짜만 말해** 사람이 무엇을 고칠지 알 수 없었다.
///
/// **이 파일이 지키는 것:** *"막힌 이유가 갈리면 화면이 값과 할 일을 말할 수 있다."*
/// **문장 자체는 여기서 못 지킨다** — App에 테스트 타깃이 없다. Core는 **어느 case인가**까지만 지키고
/// 문장은 실기기로 본다.
///
/// **다른 곳이 안 덮는 것:** 규칙 1의 **판정**(위반인가 아닌가)은 `RuleOneTests`·`RuleOneTimeTests`가 이미 덮고
/// **그 판정은 옳다** — 이 파일이 잡는 것은 판정이 아니라 **판정을 화면에 옮기는 말**이다.
/// 최종 쌍으로 검사하는 것(`applying:to:`)은 `RuleOneStaleDraftTests`가 덮는다.
///
/// **⚠️ 단계 0에서 통과한 셋(4·5·6)은 스텁으로도 통과했다 — 그 시점엔 아무것도 증명하지 않았다.**
/// 스텁이 `.dayBeforeDeadline`을 항상 돌려줬기 때문이다. **구현이 들어간 뒤에야 과잉 분기 그물이 된다.**
/// (규칙 2 — "안 고쳤다면 이 값이 달랐을까"를 계산하면 그 셋은 **안 달랐다.**)
final class Rule1BlockTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func d(_ m: Int, _ day: Int, _ h: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: day, hour: h))!
    }
    private func item(due: String?, resurface: String?) -> ResolvedItem {
        var f: [String: String] = ["type": "info-action", "raw": "시험"]
        if let due { f["due"] = due }
        if let resurface { f["resurface"] = resurface }
        return ResolvedItem(id: "x", fields: f, deleted: false, confirmed: true,
                            createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }
    private func block(_ due: String?, _ resurface: String?, _ now: Date) -> ItemSchedule.Rule1Block? {
        ItemSchedule.rule1Block(applying: [:], to: item(due: due, resurface: resurface),
                                now: now, calendar: utc)
    }

    // MARK: ★ 판정선 — 시각 위반이 따로 갈려야 한다

    /// **★ 같은 날 늦은 시각.** 사람이 **날짜는 이미 맞춰 뒀고 시각만 늦다.**
    /// 지금 화면은 「마감 **하루 전**(**8월 10일**)까지만」이라 말하는데,
    /// 사용자는 이미 8월 10일로 맞춰 뒀으므로 **무엇을 고칠지 알 수 없다.** 이 줄이 그 자리다.
    func testTimed_sameDayLater_isAtOrBeforeDeadline() {
        XCTAssertEqual(block("2026-08-10T08:00", "2026-08-10T09:00", d(8, 2)),
                       .atOrBeforeDeadline(deadline: "2026-08-10T08:00"),
                       "★ 시각 위반은 따로 갈려야 한다 — 할 일이 '시각을 앞으로'이기 때문")
    }

    /// **★ `deadline`이 마감 시각을 그대로 담는다.** 화면이 「마감(**8월 10일 08:00**)보다 늦어요」라고
    /// 말하려면 시·분이 있어야 한다. 날짜만 주면 옛 문구와 같은 정보량이라 아무것도 안 고쳐진다.
    func testTimed_capCarriesTheDeadlineTime() {
        guard case let .atOrBeforeDeadline(deadline)? = block("2026-08-10T08:00", "2026-08-12T07:00", d(8, 2)) else {
            return XCTFail("★ 시각 위반이 갈리지 않았다")
        }
        XCTAssertEqual(deadline, "2026-08-10T08:00", "★ 시·분이 그대로 실려야 화면이 시각을 말할 수 있다")
        XCTAssertNotNil(ItemSchedule.timeOfDay(deadline), "★ 시각이 살아 있어야 한다")
    }

    /// **★ 다른 날 + 시각.** 날짜를 당겨야 하는 경우도 **같은 규칙**(미리 알림 ≤ 마감)이라 같은 case다.
    /// 경우를 셋으로 쪼개지 않는다 — 사람이 할 일은 **시각 유무 하나로만** 갈린다.
    func testTimed_laterDay_isAlsoAtOrBeforeDeadline() {
        XCTAssertEqual(block("2026-08-10T08:00", "2026-08-12T07:00", d(8, 2)),
                       .atOrBeforeDeadline(deadline: "2026-08-10T08:00"))
    }

    // MARK: 그물 — 여기는 안 바뀌어야 한다 (⚠️ 단계 0에서는 스텁으로도 통과했다)

    /// 시각 없는 미리 알림 → 마감 하루 전. `cap` = 마감−1일, `deadline` = 마감.
    /// **둘 다 필요하다** — 화면이 「미리 알림을 **8월 9일** 이전으로 옮겨 주세요 — 마감은 **8월 10일**이에요」라고
    /// 두 숫자를 말하기 때문이다.
    func testDateOnly_sameDay_isDayBeforeDeadline() {
        XCTAssertEqual(block("2026-08-10", "2026-08-10", d(8, 2)),
                       .dayBeforeDeadline(cap: "2026-08-09", deadline: "2026-08-10"))
    }
    func testDateOnly_laterDay_isDayBeforeDeadline() {
        XCTAssertEqual(block("2026-08-10", "2026-08-12", d(8, 2)),
                       .dayBeforeDeadline(cap: "2026-08-09", deadline: "2026-08-10"))
    }
    /// 마감에 시각이 있어도 **미리 알림이 date-only면** 날짜 규칙이다(상한 = 마감−1일).
    func testDateOnlyResurface_timedDue_stillDayBefore() {
        XCTAssertEqual(block("2026-08-10T08:00", "2026-08-10", d(8, 2)),
                       .dayBeforeDeadline(cap: "2026-08-09", deadline: "2026-08-10T08:00"))
    }

    /// **위반이 아니면 nil** — 막지 않으니 할 말도 없다. 판정은 `violatesRule1` 하나만 본다(갈릴 수 없다).
    func testNotViolating_isNil() {
        XCTAssertNil(block("2026-08-10", "2026-08-09", d(8, 2)), "마감−1일 = 통과")
        XCTAssertNil(block("2026-08-10T08:00", "2026-08-10T07:00", d(8, 2)), "lead 1시간 = 통과")
        XCTAssertNil(block("2026-08-10T08:00", "2026-08-10T08:00", d(8, 2)), "정각(미리 알림=마감) = 허용")
        XCTAssertNil(block("2026-08-10", nil, d(8, 2)), "미리 알림 없음 = 위반할 것이 없다")
    }

    /// **마감 없음 / 마감 지남 → nil.** 규칙 1이 잠드는 구간이다.
    /// **★ A(지난 마감 상한 N=7)가 나중에 여기를 뒤집는다** — 마감 지남이 `.tooFarWhilePastDue`가 된다.
    /// 그때 이 시험의 둘째 단정을 바꾸고 **왜 바꾸는지**를 여기 적을 것(worklog 2026-08-07 §4-C).
    func testNoOrPastDue_isNil_forNow() {
        XCTAssertNil(block(nil, "2026-08-12", d(8, 2)), "마감 없음")
        XCTAssertNil(block("2026-07-31", "2026-08-14", d(8, 7)), "마감 지남 — A가 오면 여기가 바뀐다")
    }

    /// **최종 쌍으로 판정한다** — `violatesRule1(applying:to:)`와 같은 입력 규약.
    /// 저장값 위에 이번 변경만 얹은 쌍을 본다(2026-08-06 (a)와 같은 자리).
    func testUsesFinalPair_notStoredPairAlone() {
        let stored = item(due: "2026-08-10T08:00", resurface: "2026-08-10T07:00")   // 지금은 적법
        XCTAssertNil(ItemSchedule.rule1Block(applying: [:], to: stored, now: d(8, 2), calendar: utc))
        XCTAssertEqual(ItemSchedule.rule1Block(applying: ["resurface": "2026-08-10T09:00"],
                                               to: stored, now: d(8, 2), calendar: utc),
                       .atOrBeforeDeadline(deadline: "2026-08-10T08:00"),
                       "이번 변경을 얹은 최종 쌍으로 판정한다")
    }
}
