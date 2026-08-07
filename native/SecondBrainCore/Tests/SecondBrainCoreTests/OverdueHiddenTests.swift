import XCTest
@testable import SecondBrainCore

/// **늦었는데 숨겨진 것 — D** (2026-08-07).
///
/// 규칙 1은 *"항목이 자기 마감을 지날 때까지 숨는 것"* 을 막는데 **마감이 과거면 두 겹이 다 잠든다**
/// (`resurfaceUpperBound`·`violatesRule1`의 `dd > now` 가드). 지난 것을 미루려면 그 느슨함이 필요해서
/// 그렇게 정한 것이라 **규칙이 틀린 게 아니다.** 문제는 그 결과가 **아무 표시 없이** 일어난다는 것이다.
///
/// **이 파일이 세우는 불변식:** *"늦은 일은 숨더라도, 숨었다는 것이 보인다."*
/// 판정만 만든다 — **저장값은 안 바꾼다**(숨기는 것 자체는 사람이 시킨 것이다).
///
/// **다른 곳이 안 덮는 것:** 규칙 1 자체의 판정은 `RuleOneTests`·`RuleOneTimeTests`가,
/// "검사한 쌍 ≠ 저장되는 쌍"은 `RuleOneStaleDraftTests`가 덮는다. 여기는 **규칙이 잠든 구간**이다.
///
/// ⚠️ 아래 두 재현은 **실제 iCloud 데이터에서 읽은 값 그대로**다(2026-08-07 14:3x 전수 스캔, live 106개 중 딱 둘).
///
/// **⚠️ `E75C2531`은 그날 안에 해소됐다 — 2026-08-07 15:32에 사용자가 폰에서 손으로
/// `due=2026-08-14 resurface=2026-08-10`으로 고쳤다**(마감을 새로 잡고 미리 알림을 그 앞으로).
/// 그래서 **16:40 재스캔에서는 걸리는 것이 `AF9BAB30` 하나뿐이다.** 위 재현은 그 사이(10:06~15:32)의
/// 실제 상태이고, **이 시험이 지키는 것은 그 상태가 다시 생겼을 때 보이게 하는 것**이다.
/// (그 손편집은 우리가 이 건을 논의한 **뒤에** 일어났으므로, "사람은 원래 마감을 새로 잡고 싶어한다"는
/// 근거로 쓰면 안 된다 — 독립적인 관찰이 아니다.)
final class OverdueHiddenTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func d(_ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: day, hour: h, minute: min))!
    }
    private func item(_ fields: [String: String]) -> ResolvedItem {
        ResolvedItem(id: "x", fields: fields, deleted: false, confirmed: true,
                     createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }

    // MARK: ★ 재현 — 실데이터 두 건

    /// **`E75C2531` 「우리 샌드박스 협력 병원 빨리 선정 해야 됩니다」.**
    /// 마감 2026-07-31에 실제 업무인데, **2026-08-07 10:06에 폰에서 미루기(+7일)** 를 눌러
    /// 미리 알림이 08-14가 됐다. 그 순간부터 **일주일 지난 일이 다시 일주일 더 숨는다.**
    ///
    /// 전제 셋을 먼저 못박는다 — **지금 아무 신호가 없다**는 것이 이 항목의 존재 이유다.
    func testSandbox_realItem_lateAndHidden_withNoSignalToday() {
        let now = d(8, 7, 15)
        let it = item(["type": "info-action", "due": "2026-07-31", "resurface": "2026-08-14",
                       "raw": "우리 샌드박스 협력 병원 빨리 선정 해야 됩니다"])

        // 전제 ① 규칙 1이 잠들어 있다 — 마감이 과거라 저장 검사가 안 돈다.
        XCTAssertFalse(ItemSchedule.violatesRule1(resurface: it.resurface, due: it.due,
                                                  now: now, calendar: utc),
                       "전제: 마감이 과거라 규칙 1은 이 쌍을 위반이라 하지 않는다")
        // 전제 ② 상한도 없다 — DatePicker가 아무 날짜나 받는다.
        XCTAssertNil(ItemSchedule.resurfaceUpperBound(due: it.due, now: now, calendar: utc),
                     "전제: 상한 자체가 없다")
        // 전제 ③ 그래서 숨는다 — 이것이 규칙 1이 막으려던 상태 그대로다.
        XCTAssertFalse(ItemSchedule.isPublished(it, now: now, calendar: utc),
                       "전제: 08-14까지 '지금 챙길 것'에 안 나온다")

        // ★ 불변식 — 숨었다는 것이 판정으로 나와야 한다.
        let v = ItemSchedule.overdueHidden(it, now: now, calendar: utc)
        XCTAssertNotNil(v, "★ 늦었는데 숨은 상태가 판정돼야 한다 — 지금은 화면이 아무 말도 안 한다")
        XCTAssertEqual(v?.lateDays, 7, "07-31 마감을 08-07에 보면 7일 늦었다")
        XCTAssertEqual(v?.returnsOn, "2026-08-14", "다시 보일 날 = 숨긴 장본인인 미리 알림 값 그대로")
    }

    /// **`AF9BAB30` 「가 - 이른 완료 시험」.** 뒤집힌 lead(미리 알림이 마감보다 23시간 뒤)의 결과.
    /// **★ 늦은 날 수가 0인데도 숨은 것은 사실이다** — 이 경계가 이 판정의 모양을 정한다.
    /// (`lateDays > 0`을 조건에 넣으면 이 건을 통째로 놓친다.)
    func testGa_realItem_hiddenEvenWhenLateDaysIsZero() {
        let now = d(8, 7, 15, 48)
        let it = item(["type": "recurrence", "recur": "daily",
                       "due": "2026-08-07T13:00", "resurface": "2026-08-08T12:00",
                       "lastDone": "2026-08-06T00:57", "lastDoneDue": "2026-08-07T13:00",
                       "raw": "가 - 이른 완료 시험"])

        XCTAssertFalse(ItemSchedule.isPublished(it, now: now, calendar: utc), "전제: 안 보인다")
        XCTAssertEqual(Recurrence.missed(it, now: now, calendar: utc), 0,
                       "전제: 놓침 칩도 0이라 이 항목엔 지금 아무 칩이 없다")

        let v = ItemSchedule.overdueHidden(it, now: now, calendar: utc)
        XCTAssertNotNil(v, "★ 오늘 13:00 마감이 지났고 내일 12:00까지 숨는다")
        XCTAssertEqual(v?.lateDays, 0, "오늘 마감이므로 늦은 날 수는 0 — 그래도 숨은 것은 사실이다")
        XCTAssertEqual(v?.returnsOn, "2026-08-08T12:00")
    }

    // MARK: 경계 — 여기서는 판정이 나오면 안 된다(과잉 표시 금지)

    /// **마감이 미래면 판정 없음** — 규칙 1이 실제로 도는 구간이라 D가 낄 자리가 아니다.
    func testFutureDue_notOverdue() {
        let it = item(["type": "info-action", "due": "2026-08-20", "resurface": "2026-08-10"])
        XCTAssertNil(ItemSchedule.overdueHidden(it, now: d(8, 7), calendar: utc))
    }

    /// **보이고 있으면 판정 없음** — 늦었어도 목록에 있으면 숨은 게 아니다.
    func testPastDue_butPublished_notHidden() {
        let it = item(["type": "info-action", "due": "2026-07-31", "resurface": "2026-08-01"])
        XCTAssertTrue(ItemSchedule.isPublished(it, now: d(8, 7), calendar: utc), "전제: 보인다")
        XCTAssertNil(ItemSchedule.overdueHidden(it, now: d(8, 7), calendar: utc))
    }

    /// **★ 대조군 — 숨기는 것은 미리 알림이지 마감이 아니다.**
    /// 미리 알림 없이 마감만 지난 항목은 게시되므로 판정이 없어야 한다.
    /// (되풀이는 마감 시각부터 게시 — `isPublished` 2절.)
    func testDueOnly_pastDue_isPublished_soNotHidden() {
        let plain = item(["type": "info-action", "due": "2026-07-31"])
        XCTAssertTrue(ItemSchedule.isPublished(plain, now: d(8, 7), calendar: utc))
        XCTAssertNil(ItemSchedule.overdueHidden(plain, now: d(8, 7), calendar: utc))

        let rec = item(["type": "recurrence", "recur": "daily", "due": "2026-08-07T06:00"])
        XCTAssertTrue(ItemSchedule.isPublished(rec, now: d(8, 7, 15), calendar: utc))
        XCTAssertNil(ItemSchedule.overdueHidden(rec, now: d(8, 7, 15), calendar: utc))
    }

    /// **꺼둔 되풀이는 제외** — "되풀이 꺼둠" 배너가 이미 그 사실을 말한다.
    /// 같은 사실에 신호를 둘 두면 위계가 죽는다(D-4의 amber/coral과 같은 종류의 손해).
    func testDormantRecurrence_excluded_bannerAlreadySaysIt() {
        let it = item(["type": "recurrence", "recur": "daily", "recurPaused": "true",
                       "due": "2026-08-02T07:00", "resurface": "2026-08-20T07:00"])
        XCTAssertFalse(ItemSchedule.isPublished(it, now: d(8, 7), calendar: utc), "전제: 안 보인다")
        XCTAssertNil(ItemSchedule.overdueHidden(it, now: d(8, 7), calendar: utc),
                     "꺼둠은 사람이 시킨 것이고 배너가 이미 말한다")
    }

    /// **마감이 없으면 판정 없음** — "늦음"이 정의되지 않는다.
    func testNoDue_notOverdue() {
        let it = item(["type": "info-action", "resurface": "2026-08-20"])
        XCTAssertNil(ItemSchedule.overdueHidden(it, now: d(8, 7), calendar: utc))
    }

    /// **분류가 마감을 안 쓰면 판정 없음** — 게이트를 화면과 같이 탄다(`ClassSpecCatalog`).
    func testClassWithoutDue_notOverdue() {
        let it = item(["type": "info", "due": "2026-07-31", "resurface": "2026-08-20"])
        XCTAssertNil(ItemSchedule.overdueHidden(it, now: d(8, 7), calendar: utc))
    }

    // MARK: 값 — "얼마나 늦었나"는 날짜 단위로 센다

    /// 놓침(`missedCount`)과 같은 규약 — **날짜 단위**로 세고 시각은 안 본다.
    /// 어제 23:59 마감을 오늘 00:01에 보면 **1일**이다(시간으로는 2분).
    func testLateDays_countsCalendarDays_notHours() {
        let it = item(["type": "info-action", "due": "2026-08-06T23:59", "resurface": "2026-08-20"])
        XCTAssertEqual(ItemSchedule.overdueHidden(it, now: d(8, 7, 0, 1), calendar: utc)?.lateDays, 1)
    }

    /// 마감이 date-only여도 같다 — 자정 기준.
    func testLateDays_dateOnlyDue() {
        let it = item(["type": "info-action", "due": "2026-08-01", "resurface": "2026-08-20"])
        XCTAssertEqual(ItemSchedule.overdueHidden(it, now: d(8, 7, 9), calendar: utc)?.lateDays, 6)
    }
}
