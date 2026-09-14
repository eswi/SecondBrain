import XCTest
@testable import SecondBrainCore

/// Stage 1 (양력 반복) — 새 분류 `recurrence`(되풀이) 추가가 **비파괴**임을 고정한다.
/// 새 key는 자기 스펙에만 작용하고, 기존 분류·미분류 판정은 불변이어야 한다(조사 Q7).
/// (2026-09-14 재편으로 「기존」의 얼굴이 바뀌었다 — 약속·일정 빠짐 · 지식·추억 들어옴 · 정보의 유효 기간. 그 변화는 결정이고, 여기선 그 뒤의 불변을 본다.)
final class RecurrenceClassTests: XCTestCase {

    func testRecurrence_spec_usesDueAsAnchorAndResurface() {
        let spec = ClassSpecCatalog.spec("recurrence")
        XCTAssertNotNil(spec, "되풀이 분류가 등록돼 있어야")
        XCTAssertTrue(ClassSpecCatalog.uses("recurrence", .due))       // 마감 = 회차 앵커
        XCTAssertTrue(ClassSpecCatalog.uses("recurrence", .resurface)) // 미리 알림 = 게시 시작(lead)
        XCTAssertTrue(ClassSpecCatalog.uses("recurrence", .photo))
        XCTAssertTrue(ClassSpecCatalog.uses("recurrence", .location))
        XCTAssertEqual(spec?.title(for: .due), "회차 시각")
        XCTAssertEqual(spec?.title(for: .resurface), "미리 알림")
    }

    func testExistingClasses_unchanged() {
        // 주차: 마감 안 씀, 다시 보기 씀 (불변)
        XCTAssertFalse(ClassSpecCatalog.uses("parking", .due))
        XCTAssertTrue(ClassSpecCatalog.uses("parking", .resurface))
        // 아이디어·원칙(그리고 09-14에 온 지식·추억): 마감·다시 보기 둘 다 안 씀 (불변)
        for k in ["idea", "principle", "knowledge", "moment"] {
            XCTAssertFalse(ClassSpecCatalog.uses(k, .due), "\(k) due 불변")
            XCTAssertFalse(ClassSpecCatalog.uses(k, .resurface), "\(k) resurface 불변")
        }
        // 정보: 마감은 안 쓰고, 다시 보기는 **보이되 시점이 아니다**(2026-09-14 「유효 기간」 · classification-v2-design.md §1-3).
        // ⚠️ 옛 단정 「info resurface 불변(안 씀)」은 그날 사용자 결정으로 바뀐 것이다 — 구현 회귀가 아니다.
        //    시점 쪽 결정은 `ClassGateTests.testInfo_validUntil_isVisibleButNotASchedule`이 지킨다.
        XCTAssertFalse(ClassSpecCatalog.uses("info", .due), "info due 불변")
        XCTAssertTrue(ClassSpecCatalog.uses("info", .resurface), "info는 유효 기간을 보인다(09-14)")
        XCTAssertFalse(ClassSpecCatalog.schedules("info", .resurface), "그러나 시점은 아니다(09-14)")
        // 할 일: 둘 다 씀 (불변)
        XCTAssertTrue(ClassSpecCatalog.uses("info-action", .due))
        XCTAssertTrue(ClassSpecCatalog.uses("info-action", .resurface))
    }

    func testCatalog_hasEightClasses_fallbackIntact() {
        XCTAssertEqual(ClassSpecCatalog.all.count, 8)   // 여섯(할일·정보·지식·아이디어·원칙·추억) + 주차 + 되풀이 (2026-09-14 재편 후에도 8)
        // 미등록/미분류는 여전히 '전부 씀' 폴백 (버림 편향 금지)
        XCTAssertTrue(ClassSpecCatalog.uses(nil, .due))
        XCTAssertTrue(ClassSpecCatalog.uses("unknown-key", .resurface))
    }
}
