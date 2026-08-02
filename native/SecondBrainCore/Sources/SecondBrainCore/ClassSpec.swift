import Foundation

/// §7 분류–세부정보 **표의 정본**(Stage D3-A — Core 이동). Foundation 전용: 색·심볼 같은 시각 메타는 여기 없다.
///
/// D1에서 이 표는 App 타깃(`ClassDef.swift`)에 있었다. 하지만 §7 (c)의 **판정**(알림·"곧 닥칠 것")은
/// `ItemSchedule`(Core)이 하고, **코어는 App을 import할 수 없다.** 그래서 표에서 순수한 부분
/// (세부정보 슬롯 · 분류별 "쓰는지" 집합 · 제목 재정의)만 여기로 옮겼다. App의 `ClassDef`/`ClassCatalog`는
/// 이 표에 **위임**하고 시각 메타(`TypeMeta`·`Color`·심볼)만 얹는다 — 정본은 여기 한 곳, 복사본 없음.
///
/// **경계:** §2 `TypeCatalog`(6종 시각 메타)는 보호자산이라 App에 그대로 둔다. 주차의 시각 메타도 App.
/// 여기 있는 건 "어떤 분류가 어떤 세부정보를 쓰나 + 그걸 뭐라 부르나"뿐이다.

/// 공통 그릇의 세부정보 슬롯. 필요할 때 늘린다.
/// (원문·성역 메타·audio·question은 **분류 무관 상시**라 §7 지배 대상 밖 → 여기 없음.)
public enum Detail: Hashable, CaseIterable, Sendable {
    case due        // 마감
    case resurface  // 다시 보기
    case photo      // 사진 (미디어 포인터)
    case location   // 사진 EXIF 촬영 위치

    /// 이 세부정보의 **기본 제목(=의미)**. §7 (b). 분류가 재정의하지 않으면 이 라벨을 쓴다(할일 기준 = 가장 일반적).
    /// 실사용 화면 라벨이므로 개발용 영문 접미사 "(Due)"/"(Resurface)"는 빼고 간결한 한글로 통일한다.
    public var defaultTitle: String {
        switch self {
        case .due:       return "마감"
        case .resurface: return "다시 보기"
        case .photo:     return "사진"
        case .location:  return "위치"
        }
    }
}

/// 한 분류의 §7 정의 중 **시각 메타를 뺀 전부** = 쓰는 세부정보 집합 + 제목 재정의. 집합에 있으면 '씀'.
/// (기본층/유연층 구분 없음 — 모든 분류가 이 한 구조로 평등하다: §7 "모든 분류 평등".)
public struct ClassSpec: Sendable {
    /// 이벤트 `type` 값. (주차 = `"parking"` — 한글 "주차"가 아니다.)
    public let key: String
    public let uses: Set<Detail>
    /// 분류별 **제목(=의미) 재정의**(§7 (b)). 같은 데이터라도 분류마다 다른 이름표.
    /// 비어 있으면 `Detail.defaultTitle`. 예: due가 할일엔 "마감", 약속엔 "언제", 일정엔 "일시".
    public let titles: [Detail: String]

    public init(key: String, uses: Set<Detail>, titles: [Detail: String] = [:]) {
        self.key = key
        self.uses = uses
        self.titles = titles
    }

    public func uses(_ detail: Detail) -> Bool { uses.contains(detail) }
    /// 이 분류에서 detail의 제목(=의미). 재정의 없으면 기본.
    public func title(for detail: Detail) -> String { titles[detail] ?? detail.defaultTitle }
}

/// 모든 분류의 **평등한 정본 목록**. 층 구분 없이 한 축.
/// 순서는 **표시 순서일 뿐**(계층 아님): §2 6종 → 주차. 미분류(nil)는 분류 지정 대상이 아니라 여기 없다.
public enum ClassSpecCatalog {
    /// 세부정보 정의(§7 (a) 쓸지/안 쓸지). 기준(mirror) = 마감·다시보기·사진·위치 모두 씀.
    /// 분류별 차등:
    /// - **주차** = 마감(due) 안 씀(§7 "주차는 사진·위치·본문으로 충분" — Stage C).
    /// - **정보·아이디어·원칙**(`noTime`) = 마감·다시보기 **둘 다 안 씀** — 참고 지식·발상·상시 원칙은
    ///   시점이 본질이 아니다(원칙은 ambient 상시라 날짜·마감이 근본적으로 안 맞음).
    public static let all: [ClassSpec] = {
        let mirror: Set<Detail> = [.due, .resurface, .photo, .location]
        let noTime: Set<Detail> = [.photo, .location]   // 마감·다시보기 안 씀(정보·아이디어·원칙)
        return [
            ClassSpec(key: "promise",     uses: mirror,
                      titles: [.due: "언제", .resurface: "미리 알림"]),   // 약속: 날짜=만나는 시점
            ClassSpec(key: "event",       uses: mirror,
                      titles: [.due: "일시", .resurface: "미리 알림"]),   // 일정: 날짜=일어나는 시점
            ClassSpec(key: "info-action", uses: mirror),   // 할일: 기본("마감"·"다시 보기")
            ClassSpec(key: "info",        uses: noTime),
            ClassSpec(key: "idea",        uses: noTime),
            ClassSpec(key: "principle",   uses: noTime),
            ClassSpec(key: "parking",     uses: mirror.subtracting([.due])),
            // 되풀이(반복) — 8번째 분류(recurrence-design.md). 기준 날짜(마감·미리 알림)를 쓴다.
            // 주기·자동완성·꺼두기·마지막완료는 별도 필드(Detail 슬롯 아님) — memory-philosophy §7 밖의 반복 전용.
            ClassSpec(key: "recurrence",  uses: mirror,
                      titles: [.due: "날짜", .resurface: "미리 알림"]),
        ]
    }()

    /// key → 정의(빠른 조회).
    public static let byKey: [String: ClassSpec] = {
        var m: [String: ClassSpec] = [:]
        for s in all { m[s.key] = s }
        return m
    }()

    /// key → 정의. **미분류(nil)·미등록 key(discard 등)는 nil** = "정의 없음". 폴백은 `uses(_:_:)`에 있다.
    public static func spec(_ key: String?) -> ClassSpec? {
        guard let key else { return nil }
        return byKey[key]
    }

    /// **"이 분류가 이 칸을 쓰는가"의 유일한 답**(§7 (a)). 화면(상세 "시간 설정")과 판정(알림·"곧 닥칠 것")이
    /// **같은 함수**를 본다 — 폴백이 두 곳에 흩어지면 보이는 것과 울리는 것이 어긋난다.
    ///
    /// **정의 없는 분류(미분류 nil·빈 문자열·`discard`·미등록 key)는 전부 '씀'으로 폴백한다.**
    /// 사람이 적어둔 날짜가 분류가 안 붙었다는 이유로 조용히 사라지면 안 된다(§7 — 기억은 사람 것).
    public static func uses(_ key: String?, _ detail: Detail) -> Bool {
        spec(key)?.uses(detail) ?? true
    }
}
