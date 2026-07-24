import SwiftUI
import SecondBrainCore

/// 유연층 분류 — 사용자가 자유롭게 늘리는 층. **§2 기본층(`TypeCatalog`, 고정)과 완전 분리**된 별도 레지스트리.
/// "공통 그릇 + 분류별 필드 정의"(classification-redesign-open-questions.md D4)의 실체:
/// 데이터 그릇은 공통(이벤트 소싱 fields), **쓰는 필드만 분류별**로 여기서 정의한다.
///
/// 자동 분류는 **지금은** 이 층을 참조하지 않는다(임시) — `InboxModel.classifyFields`의 `validTypes`(§2)에 없어
/// AI가 유연층 type을 찍지 못한다(사람 수동 지정만). **"안 하기로 한 것"이 아니라 "아직 안 한 것"** — 원래
/// 의도는 유연층도 자동분류 대상이며, 유연층이 쌓이면 편입 예정(`classification-redesign-open-questions.md` O4).
/// 지금 수동뿐인 이유 = §3 프롬프트(보호 자산) 보류 + 유연층이 주차위치 하나뿐. 관리 UI는 나중 — D4.
enum FlexTypeCatalog {
    static let parking = TypeMeta(key: "parking", label: "주차 위치",
                                  color: Color(hex: 0x34D399), symbol: "car.fill")

    /// 상세 분류 선택에 노출할 유연층 종류들.
    static let assignable: [TypeMeta] = [parking]
}

/// 기본층(§2) + 유연층 **통합 조회**. `TypeCatalog`(보호 자산)는 손대지 않고 여기서 합쳐 본다.
///
/// **주차위치는 추가 입력 필드가 없다** — 사진 + GPS(EXIF) + 본문으로 이미 충분하므로 그릇에 새 필드를
/// 얹지 않고 성역 카드가 그대로 보여준다(2026-07-24 Stage 4 재설계). "분류가 무엇을 보여주고/중요한지
/// 결정"하는 개념(이미 있는 정보의 표시·중요도 선택)의 진짜 구현은 둘째 유연층이나 due 숨김 같은 실제
/// 요구가 생길 때 — `classification-redesign-open-questions.md` 참조. 지금은 종류 등록만 한다.
enum ClassRegistry {
    /// 분류 선택 메뉴 전체: 기본층 6 + 유연층. (§2 먼저, 유연층 뒤.)
    static var assignable: [TypeMeta] { TypeCatalog.assignable + FlexTypeCatalog.assignable }

    /// key → 메타. 유연층 우선 조회 후 없으면 기본층/미분류(`TypeCatalog.meta`).
    static func meta(_ key: String?) -> TypeMeta {
        if let k = key, let f = FlexTypeCatalog.assignable.first(where: { $0.key == k }) { return f }
        return TypeCatalog.meta(key)
    }
}
