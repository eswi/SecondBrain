import SwiftUI
import SecondBrainCore

/// 유연층 분류 — 사용자가 자유롭게 늘리는 층. **§2 기본층(`TypeCatalog`, 고정)과 완전 분리**된 별도 레지스트리.
/// "공통 그릇 + 분류별 필드 정의"(classification-redesign-open-questions.md D4)의 실체:
/// 데이터 그릇은 공통(이벤트 소싱 fields), **쓰는 필드만 분류별**로 여기서 정의한다.
///
/// 자동 분류는 이 층을 **절대 참조하지 않는다** — `InboxModel.classifyFields`의 `validTypes`(§2)에 없어
/// AI가 유연층 type을 찍지 못한다(사람 수동 지정만). 지금은 주차위치 하나 하드코딩(관리 UI는 나중 — D4).
enum FlexTypeCatalog {
    static let parking = TypeMeta(key: "parking", label: "주차 위치",
                                  color: Color(hex: 0x34D399), symbol: "car.fill")

    /// 상세 분류 선택에 노출할 유연층 종류들.
    static let assignable: [TypeMeta] = [parking]
}

/// 분류별 필드 정의 — 상세 화면에서 편집·표시할 **가변 텍스트 필드**. 성역/가변·필수/선택을 코드로 명시.
struct FieldSpec: Identifiable {
    enum Kind { case longText }        // 지금은 긴 텍스트만(위치·메모). date 등은 나중 확장.
    let key: String
    let label: String
    let placeholder: String
    let kind: Kind
    let sanctuary: Bool                // true면 불변(create 성역) — 지금 유연층 텍스트는 전부 가변(false)
    let required: Bool                 // 표시만(별표) — 저장 강제는 안 함(D4: 일단 찍어두고 나중에 채우기 허용)
    var id: String { key }
}

/// 한 분류가 쓰는 필드 묶음.
struct ClassSchema {
    let key: String
    let fields: [FieldSpec]
}

/// 기본층(§2) + 유연층 **통합 조회**. `TypeCatalog`(보호 자산)는 손대지 않고 여기서 합쳐 본다.
enum ClassRegistry {
    /// 분류 선택 메뉴 전체: 기본층 6 + 유연층. (§2 먼저, 유연층 뒤.)
    static var assignable: [TypeMeta] { TypeCatalog.assignable + FlexTypeCatalog.assignable }

    /// key → 메타. 유연층 우선 조회 후 없으면 기본층/미분류(`TypeCatalog.meta`).
    static func meta(_ key: String?) -> TypeMeta {
        if let k = key, let f = FlexTypeCatalog.assignable.first(where: { $0.key == k }) { return f }
        return TypeCatalog.meta(key)
    }

    /// 이 분류의 필드 스키마(유연층만 가짐). 기본층·미분류는 nil → 상세에 분류별 필드 없음.
    static func schema(_ key: String?) -> ClassSchema? {
        switch key {
        case "parking":
            return ClassSchema(key: "parking", fields: [
                FieldSpec(key: "location", label: "위치",
                          placeholder: "예: 지하 2층 B구역, 빨간 기둥 옆",
                          kind: .longText, sanctuary: false, required: true),
                FieldSpec(key: "memo", label: "메모",
                          placeholder: "예: 엘리베이터에서 왼쪽으로 30m",
                          kind: .longText, sanctuary: false, required: false),
            ])
        default:
            return nil
        }
    }
}
