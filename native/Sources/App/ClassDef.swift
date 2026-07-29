import SwiftUI
import SecondBrainCore

/// §7 분류–세부정보 모델의 **App 층**(Stage D3-A — 표는 Core로 이동, 여기는 시각 메타 + 위임).
///
/// §7(`docs/native/memory-philosophy.md`): 분류는 새 데이터 구조가 아니라 **공통 그릇 위의 정의**다.
/// 그 정의 중 **순수한 표**(세부정보 슬롯 `Detail` · 분류별 `uses` 집합 · 제목 재정의)는
/// Core `ClassSpec.swift`가 **정본**이다 — §7 (c)의 판정(알림·"곧 닥칠 것")을 하는 `ItemSchedule`이
/// Core에 있고 코어는 App을 import할 수 없기 때문. 여기서는 그 표에 **시각 메타만 얹는다**.
/// **기본층/유연층 구분 없음**(§7 "모든 분류 평등") — 주차위치도 그중 하나일 뿐이다.
///
/// **경계:** §2 `TypeCatalog`(6종 시각 메타)는 **보호자산이라 그대로 두고 참조만** 한다. §3 프롬프트·
/// `validTypes`·`MergeEngine` 무변경. 이 층은 표시 정책만. 자동분류는 §3/O4 소관(§7이 앞당기지 않음).

/// 한 분류의 §7 정의 = **시각 메타 + Core 표(`ClassSpec`)**. 세부정보 사용 여부·제목은 여기서 다시
/// 정의하지 않고 `spec`을 그대로 쓴다(복사본 없음 — 정본은 `ClassSpecCatalog.all` 한 곳).
struct ClassDef {
    let meta: TypeMeta
    let spec: ClassSpec

    var key: String? { meta.key }
}

/// 모든 분류의 평등한 목록 = Core 정본 순서(§2 6종 → 주차)에 **시각 메타를 붙인 것**.
/// 미분류(nil)는 분류 지정 대상이 아니라 Core 표에도 여기에도 없다.
enum ClassCatalog {
    /// 시각 메타: 6종은 §2 `TypeCatalog`(보호자산) 참조, 주차는 여기서 정의(D1의 유연층 흡수분).
    /// Core 표(`ClassSpecCatalog.all`)를 그대로 훑으므로 **분류 추가는 Core 한 곳만** 고치면 된다.
    static let all: [ClassDef] = {
        let parking = TypeMeta(key: "parking", label: "주차 위치",
                               color: Color(hex: 0x34D399), symbol: "car.fill")
        return ClassSpecCatalog.all.map { spec in
            ClassDef(meta: spec.key == parking.key ? parking : TypeCatalog.meta(spec.key), spec: spec)
        }
    }()

    /// key → 정의(빠른 조회).
    static let byKey: [String: ClassDef] = {
        var m: [String: ClassDef] = [:]
        for d in all { if let k = d.key { m[k] = d } }
        return m
    }()
}
