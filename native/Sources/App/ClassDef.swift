import SecondBrainCore

/// §7 분류–세부정보 모델의 코드 틀 (Stage B — 틀만, 동작 0).
///
/// §7(`docs/native/memory-philosophy.md`): 분류는 새 데이터 구조가 아니라 **공통 그릇 위의 정의**다.
/// 이 틀은 그중 가장 먼저 필요한 한 가지 — **"각 분류가 어떤 세부정보를 쓰는가"(§7 (a) 쓸지/안 쓸지)** 만
/// 표현한다. 제목(=의미)·동작·누가 값·개수(§7 (b)(c)(d))는 **실제 요구가 생기는 Stage D에서** 코드가
/// 자란다 — 지금 미리 넣으면 빈 구조 = 과잉추상화(§7-0의 "만능 엔진" 경고, D5).
///
/// **경계:** §2 `TypeCatalog`(시각 메타)·§3 프롬프트·`validTypes`·`MergeEngine` 무변경. 이 층은 표시 정책만.
/// 자동분류는 여전히 §3/O4 소관(§7이 자동분류를 앞당기지 않는다).
///
/// **Stage B 상태: 아무 화면도 이 틀을 읽지 않는다 → 앱 동작 0.** DetailView가 이걸 읽어 주차위치에서
/// 마감을 숨기는 첫 실제 동작은 Stage C.

/// 공통 그릇의 세부정보 슬롯. Stage C에 필요한 것만 먼저 — 필요해지면 늘린다.
/// (원문·성역 메타·audio·question은 **분류 무관 상시**라 §7 지배 대상 밖 → 여기 없음.)
enum Detail: Hashable {
    case due        // 마감 (Due)
    case resurface  // 다시 보기 (Resurface)
    case photo      // 사진 (미디어 포인터)
    case location   // 사진 EXIF 촬영 위치
}

/// 한 분류의 §7 정의. 지금은 **쓰는 세부정보의 집합**뿐 — 집합에 있으면 '씀'.
/// 기본층/유연층 구분 없음(§7 "모든 분류 평등").
struct ClassDef {
    let key: String
    let uses: Set<Detail>

    func uses(_ detail: Detail) -> Bool { uses.contains(detail) }
}

/// 분류별 `ClassDef` 목록. **§2·유연층과 무관한 §7 정의 층**(TypeMeta 안 건드림).
enum ClassCatalog {
    /// **현재 동작의 거울(Stage B):** 지금 `DetailView`는 모든 분류에 마감·다시보기를 항상 표시하고
    /// (`timeSection`), 사진·위치는 있으면 표시한다(`photoRow`, 타입 무관). 즉 분류별 차등이 아직 0 →
    /// **7개 분류(기본층 6 + 주차) 전부 네 Detail을 모두 씀**으로 서술하면 화면 동작과 정확히 일치한다.
    /// 주차의 마감 제외(첫 차등)는 Stage C.
    static let all: [String: ClassDef] = {
        let mirror: Set<Detail> = [.due, .resurface, .photo, .location]
        var m: [String: ClassDef] = [:]
        for meta in ClassRegistry.assignable {          // 기본층 6 + 유연층(주차) — 평등
            guard let key = meta.key else { continue }
            m[key] = ClassDef(key: key, uses: mirror)
        }
        return m
    }()
}

extension ClassRegistry {
    /// key → §7 정의. `meta(_:)`가 시각 메타를 통합 조회하듯, 이건 세부정보 정의를 통합 조회한다.
    /// 미분류(nil)나 목록에 없는 key는 nil.
    static func def(_ key: String?) -> ClassDef? {
        guard let key else { return nil }
        return ClassCatalog.all[key]
    }
}
