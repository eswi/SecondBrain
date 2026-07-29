import SwiftUI
import SecondBrainCore

/// **분류 평등 통합 조회**(§7 — Stage D1, D3-A). 기본층/유연층 구분이 없다: 모든 분류는 한 축에서 온다.
/// D1 이전엔 §2 `TypeCatalog`(기본층 6)와 `FlexTypeCatalog`(유연층 주차)를 concat/우선조회로 합쳤다.
///
/// 조회 경로가 둘로 갈린다(D3-A):
/// - **세부정보 표**(쓰는지·제목) → Core `ClassSpecCatalog`(정본).
/// - **시각 메타** → App `ClassCatalog`(= Core 표 + 색·심볼). §2 `TypeCatalog`는 **보호자산이라 그대로** 두고
///   미분류(nil)·미등록 key **폴백으로만** 참조한다.
enum ClassRegistry {
    /// 분류 지정 메뉴·필터에 노출할 전체 분류(표시 순서 = `ClassCatalog` 순: §2 6종 → 주차).
    static var assignable: [TypeMeta] { ClassCatalog.all.map { $0.meta } }

    /// key → 시각 메타. 등록된 분류는 `ClassCatalog`에서, **미분류·미등록은 §2 `TypeCatalog` 폴백**.
    static func meta(_ key: String?) -> TypeMeta {
        if let key, let d = ClassCatalog.byKey[key] { return d.meta }
        return TypeCatalog.meta(key)
    }

    /// (분류, 세부정보) → **제목(=의미)**. §7 (b). 분류가 재정의했으면 그 라벨, 아니면 `Detail.defaultTitle`.
    /// 미분류(nil)·미등록 key는 기본 라벨. (예: due → 할일·미분류 "마감", 약속 "언제", 일정 "일시".)
    static func title(_ key: String?, _ detail: Detail) -> String {
        ClassSpecCatalog.spec(key)?.title(for: detail) ?? detail.defaultTitle
    }

    /// "이 분류가 이 칸을 쓰나"는 여기 없다 — **화면·알림이 같은 답을 보게** Core
    /// `ClassSpecCatalog.uses(_:_:)`를 직접 쓴다(폴백 "정의 없으면 전부 씀"이 그 안에 있음).
}
