import SwiftUI
import SecondBrainCore

/// **분류 평등 통합 조회**(§7 — Stage D1). 기본층/유연층 구분이 없다: 모든 분류는 `ClassCatalog`(정본)에서
/// 온다. D1 이전엔 §2 `TypeCatalog`(기본층 6)와 `FlexTypeCatalog`(유연층 주차)를 concat/우선조회로 합쳤으나,
/// 이제 `ClassCatalog`가 둘을 **한 축의 평등한 목록**으로 담고 여기서 통합 조회한다.
///
/// §2 `TypeCatalog`(6종 시각 메타)는 **보호자산이라 그대로** 두고, 미분류(nil)·미등록 key **폴백으로만** 참조한다.
enum ClassRegistry {
    /// 분류 지정 메뉴·필터에 노출할 전체 분류(표시 순서 = `ClassCatalog` 순: §2 6종 → 주차).
    static var assignable: [TypeMeta] { ClassCatalog.all.map { $0.meta } }

    /// key → 시각 메타. 등록된 분류는 `ClassCatalog`에서, **미분류·미등록은 §2 `TypeCatalog` 폴백**.
    static func meta(_ key: String?) -> TypeMeta {
        if let key, let d = ClassCatalog.byKey[key] { return d.meta }
        return TypeCatalog.meta(key)
    }

    /// key → §7 세부정보 정의. 미분류(nil)·미등록 key는 nil.
    static func def(_ key: String?) -> ClassDef? {
        guard let key else { return nil }
        return ClassCatalog.byKey[key]
    }
}
