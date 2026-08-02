import XCTest
@testable import SecondBrainCore

/// Stage 1 (양력 반복) — 새 분류 `recurrence`(되풀이) 추가가 **비파괴**임을 고정한다.
/// 새 key는 자기 스펙에만 작용하고, 기존 7종·미분류 판정은 불변이어야 한다(조사 Q7).
final class RecurrenceClassTests: XCTestCase {

    func testRecurrence_spec_usesResurfaceNotDue() {
        let spec = ClassSpecCatalog.spec("recurrence")
        XCTAssertNotNil(spec, "되풀이 분류가 등록돼 있어야")
        XCTAssertFalse(ClassSpecCatalog.uses("recurrence", .due))      // 마감 안 씀 — 반복엔 기한 없음
        XCTAssertTrue(ClassSpecCatalog.uses("recurrence", .resurface)) // 미리 알림 = 회차 앵커
        XCTAssertTrue(ClassSpecCatalog.uses("recurrence", .photo))
        XCTAssertTrue(ClassSpecCatalog.uses("recurrence", .location))
        XCTAssertEqual(spec?.title(for: .resurface), "회차 시각")
    }

    func testExistingClasses_unchanged() {
        // 주차: 마감 안 씀, 다시 보기 씀 (불변)
        XCTAssertFalse(ClassSpecCatalog.uses("parking", .due))
        XCTAssertTrue(ClassSpecCatalog.uses("parking", .resurface))
        // 정보·아이디어·원칙: 마감·다시 보기 둘 다 안 씀 (불변)
        for k in ["info", "idea", "principle"] {
            XCTAssertFalse(ClassSpecCatalog.uses(k, .due), "\(k) due 불변")
            XCTAssertFalse(ClassSpecCatalog.uses(k, .resurface), "\(k) resurface 불변")
        }
        // 할 일: 둘 다 씀 (불변)
        XCTAssertTrue(ClassSpecCatalog.uses("info-action", .due))
        XCTAssertTrue(ClassSpecCatalog.uses("info-action", .resurface))
    }

    func testCatalog_hasEightClasses_fallbackIntact() {
        XCTAssertEqual(ClassSpecCatalog.all.count, 8)   // 6종 + 주차 + 되풀이
        // 미등록/미분류는 여전히 '전부 씀' 폴백 (버림 편향 금지)
        XCTAssertTrue(ClassSpecCatalog.uses(nil, .due))
        XCTAssertTrue(ClassSpecCatalog.uses("unknown-key", .resurface))
    }
}
