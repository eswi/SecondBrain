import SwiftUI
import SecondBrainCore

/// §7 분류–세부정보 모델의 코드 정본 (Stage D1 — 분류 평등 통합).
///
/// §7(`docs/native/memory-philosophy.md`): 분류는 새 데이터 구조가 아니라 **공통 그릇 위의 정의**다.
/// 여기서 각 분류를 **하나의 평등한 항목**으로 정의한다 — 시각 메타 + 그 분류가 **쓰는 세부정보 집합**
/// (§7 (a) 쓸지/안 쓸지). **기본층/유연층 구분 없음**(§7 "모든 분류 평등") — 주차위치도 그중 하나일 뿐이다.
/// D1 이전의 `FlexTypeCatalog`(유연층)는 여기로 흡수됐다.
///
/// 제목(=의미)·동작·누가 값·개수(§7 (b)(c)(d))는 실제 요구가 생기는 **Stage D2~ 에서** 코드가 자란다 —
/// 지금 미리 넣으면 빈 구조 = 과잉추상화(§7-0 "만능 엔진" 경고).
///
/// **경계:** §2 `TypeCatalog`(6종 시각 메타)는 **보호자산이라 그대로 두고 참조만** 한다. §3 프롬프트·
/// `validTypes`·`MergeEngine` 무변경. 이 층은 표시 정책만. 자동분류는 §3/O4 소관(§7이 앞당기지 않음).

/// 공통 그릇의 세부정보 슬롯. 필요할 때 늘린다.
/// (원문·성역 메타·audio·question은 **분류 무관 상시**라 §7 지배 대상 밖 → 여기 없음.)
enum Detail: Hashable {
    case due        // 마감 (Due)
    case resurface  // 다시 보기 (Resurface)
    case photo      // 사진 (미디어 포인터)
    case location   // 사진 EXIF 촬영 위치
}

/// 한 분류의 §7 정의 = **시각 메타 + 쓰는 세부정보 집합**. 집합에 있으면 '씀'.
/// (기본층/유연층 필드 없음 — 모든 분류가 이 한 구조로 평등하다.)
struct ClassDef {
    let meta: TypeMeta
    let uses: Set<Detail>

    var key: String? { meta.key }
    func uses(_ detail: Detail) -> Bool { uses.contains(detail) }
}

/// 모든 분류의 **평등한 정본 목록**. 층 구분 없이 한 축.
/// 순서는 **표시 순서일 뿐**(계층 아님): §2 6종 → 주차. 미분류(nil)는 분류 지정 대상이 아니라 여기 없다.
enum ClassCatalog {
    /// 세부정보 정의(§7 (a) 쓸지/안 쓸지). 기준(mirror) = 마감·다시보기·사진·위치 모두 씀.
    /// 분류별 차등:
    /// - **주차** = 마감(due) 안 씀(§7 "주차는 사진·위치·본문으로 충분" — Stage C).
    /// - **정보·아이디어·원칙**(`noTime`) = 마감·다시보기 **둘 다 안 씀** — 참고 지식·발상·상시 원칙은
    ///   시점이 본질이 아니다(원칙은 ambient 상시라 날짜·마감이 근본적으로 안 맞음). 상세에서 "시간 설정"
    ///   섹션 자체가 안 뜬다.
    /// 이 차등은 **표시 전용**(`DetailView.timeSection`이 읽어 행/섹션을 숨김) — 저장된 due/resurface 값은
    /// 안 지운다(비파괴적; 값 무효화·알림 정리 '동작'은 §7 (c), Stage D3 몫).
    static let all: [ClassDef] = {
        let mirror: Set<Detail> = [.due, .resurface, .photo, .location]
        let noTime: Set<Detail> = [.photo, .location]   // 마감·다시보기 안 씀(정보·아이디어·원칙)
        // 시각 메타: 6종은 §2 TypeCatalog(보호자산) 참조, 주차는 여기서 정의(유연층 흡수).
        let parking = TypeMeta(key: "parking", label: "주차 위치",
                               color: Color(hex: 0x34D399), symbol: "car.fill")
        return [
            ClassDef(meta: TypeCatalog.meta("promise"),     uses: mirror),
            ClassDef(meta: TypeCatalog.meta("event"),       uses: mirror),
            ClassDef(meta: TypeCatalog.meta("info-action"), uses: mirror),
            ClassDef(meta: TypeCatalog.meta("info"),        uses: noTime),
            ClassDef(meta: TypeCatalog.meta("idea"),        uses: noTime),
            ClassDef(meta: TypeCatalog.meta("principle"),   uses: noTime),
            ClassDef(meta: parking,                         uses: mirror.subtracting([.due])),
        ]
    }()

    /// key → 정의(빠른 조회).
    static let byKey: [String: ClassDef] = {
        var m: [String: ClassDef] = [:]
        for d in all { if let k = d.key { m[k] = d } }
        return m
    }()
}
