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
    /// **(a) 보이는 칸** — 상세 「시간 설정」에 줄이 생기고, 캡션·목록에 그 날짜가 노출된다.
    public let uses: Set<Detail>
    /// **(c) 시점으로 쓰는 칸** — 게시(「지금 챙길 것」)·알림·D-day·미루기가 보는 집합.
    /// **기본은 `uses`와 같다.** 갈리는 첫 분류가 **정보**다(2026-09-14): 「유효 기간」은 **보이되 시점이 아니다** —
    /// 지나도 게시·알림을 만들지 않고 살아있는 기억에 그대로 있다(`classification-v2-design.md` §1-3).
    /// ⛔ `schedules ⊆ uses`여야 한다 — 안 보이는 칸이 시점일 수는 없다(init에서 교집합으로 강제).
    public let schedules: Set<Detail>
    /// **유효 기간 칸** — 이 칸의 날짜가 지나면 그 기억은 「유효 기간이 지난 것」이다(회색 · 상세 표시).
    /// 정보만 `.resurface`. 나머지는 nil(유효 기간 개념 없음).
    public let validUntil: Detail?
    /// 분류별 **제목(=의미) 재정의**(§7 (b)). 같은 데이터라도 분류마다 다른 이름표.
    /// 비어 있으면 `Detail.defaultTitle`. 예: resurface가 할일엔 "다시 보기", 정보엔 "유효 기간", 되풀이엔 "미리 알림".
    public let titles: [Detail: String]

    public init(key: String, uses: Set<Detail>, schedules: Set<Detail>? = nil,
                validUntil: Detail? = nil, titles: [Detail: String] = [:]) {
        self.key = key
        self.uses = uses
        self.schedules = (schedules ?? uses).intersection(uses)
        self.validUntil = validUntil
        self.titles = titles
    }

    public func uses(_ detail: Detail) -> Bool { uses.contains(detail) }
    public func schedules(_ detail: Detail) -> Bool { schedules.contains(detail) }
    /// 이 분류에서 detail의 제목(=의미). 재정의 없으면 기본.
    public func title(for detail: Detail) -> String { titles[detail] ?? detail.defaultTitle }
}

/// 모든 분류의 **평등한 정본 목록**. 층 구분 없이 한 축.
/// 순서는 **표시 순서일 뿐**(계층 아님): §2 여섯 → 주차 → 되풀이. 미분류(nil)는 분류 지정 대상이 아니라 여기 없다.
///
/// **2026-09-14 재편(사용자 결정 · `docs/native/classification-v2-design.md`):**
/// - **약속(`promise`)·일정(`event`)을 뺐다** — 다른 앱이 맡는다. 남은 옛 값은 **미등록 key**로 폴백(전부 씀 · 라벨은 미분류).
/// - **지식(`knowledge`)·추억(`moment`)을 더했다** — 둘 다 시간을 안 쓴다.
/// - **정보(`info`)는 다시 보기 칸을 「유효 기간」으로 쓴다** — 보이되 시점이 아니다(`schedules` 비움 · `validUntil`).
public enum ClassSpecCatalog {
    /// 세부정보 정의(§7 (a) 쓸지/안 쓸지). 기준(mirror) = 마감·다시보기·사진·위치 모두 씀.
    /// 분류별 차등:
    /// - **주차** = 마감(due) 안 씀(§7 "주차는 사진·위치·본문으로 충분" — Stage C).
    /// - **지식·아이디어·원칙·추억**(`noTime`) = 마감·다시보기 **둘 다 안 씀** — 시간이 지나도 가치가 안 변하는 것들·
    ///   발상·상시 원칙·인생의 사건은 시점이 본질이 아니다(원칙은 ambient 상시라 날짜·마감이 근본적으로 안 맞음).
    /// - **정보** = 다시 보기를 **보이기만** 한다(「유효 기간」) — 시점 집합은 비어 있다.
    /// **주차 위치의 `type` 값.** ⚠️ 한글 "주차"가 아니다.
    /// ★ 앱이 이 분류를 이름으로 가려야 하는 자리가 생겨서 상수로 올렸다(2026-09-13) —
    /// 「주차를 처음 기억할 때 다시 보기를 오늘로」(`DetailView.remember()`).
    /// ⛔ 문자열을 양쪽에 따로 적지 않는다 — 한쪽만 고쳐지면 조용히 안 먹는다.
    public static let parkingKey = "parking"
    /// **정보**의 `type` 값 — 유효 기간(회색 판정)을 가진 유일한 분류라 상수로 둔다.
    public static let infoKey = "info"
    /// **지식**(2026-09-14 신설) — 시간이 지나도 가치가 거의 안 사라지는 기억. 화면 이름 「지식」은 사용자가 정했다.
    public static let knowledgeKey = "knowledge"
    /// **추억**(2026-09-14 신설) — 정보·지식의 가치가 아니라 **내 인생의 사건**. 화면 이름 「추억」은 사용자가 정했다.
    /// 날짜는 **아직** 안 쓴다(사용자: *"나중에 필요하면 넣는다"*) — 「추억의 날짜」(§7-1 예시)는 미래의 자리.
    public static let momentKey = "moment"

    public static let all: [ClassSpec] = {
        let mirror: Set<Detail> = [.due, .resurface, .photo, .location]
        let noTime: Set<Detail> = [.photo, .location]   // 마감·다시보기 안 씀(지식·아이디어·원칙·추억)
        return [
            ClassSpec(key: "info-action", uses: mirror),   // 할일: 기본("마감"·"다시 보기")
            // **정보 — 「유효 기간」(2026-09-14 사용자 결정).** 다시 보기 칸에 제목만 바꿔 저장한다(새 필드 없음).
            // **보이되 시점이 아니다:** `schedules`가 비어 있어 게시·알림·미루기가 이 날짜를 안 본다.
            // 지나면 목록에서 회색이 되고(`ItemSchedule.isExpired`) 자리는 살아있는 기억 그대로.
            // ⛔ 이 줄을 `schedules: nil`(=uses)로 바꾸면 **유효 기간이 지난 정보가 「지금 챙길 것」에 뜬다** —
            //    `ClassGateTests`의 정보 시험이 그것을 막는다(깨지면 구현이 아니라 결정을 의심).
            ClassSpec(key: infoKey,       uses: noTime.union([.resurface]), schedules: [],
                      validUntil: .resurface, titles: [.resurface: "유효 기간"]),
            ClassSpec(key: knowledgeKey,  uses: noTime),
            ClassSpec(key: "idea",        uses: noTime),
            ClassSpec(key: "principle",   uses: noTime),
            ClassSpec(key: momentKey,     uses: noTime),
            ClassSpec(key: parkingKey,    uses: mirror.subtracting([.due])),
            // 되풀이(반복) — 8번째 분류(recurrence-design.md §3-A).
            // **마감(due) = 회차 앵커(회차 시각)**, **미리 알림(resurface) = 게시 시작(lead)** — 일반 항목과 동일 역할.
            // 완료 시 마감을 다음 회차로, 미리 알림도 같은 간격 전진(lead 보존). 마감만 있으면 마감 시각부터 보임(게이트 시각 인지).
            // 주기·자동완성·꺼두기·마지막완료는 별도 필드(Detail 슬롯 아님).
            ClassSpec(key: "recurrence",  uses: mirror,
                      titles: [.due: "회차 시각", .resurface: "미리 알림"]),
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

    /// **"이 분류가 이 칸을 시점으로 쓰는가"의 유일한 답**(§7 (c)). 게시(`ItemSchedule.isPublished`)·알림·D-day·
    /// 미루기가 본다. `uses`와 다른 답을 주는 분류는 **정보 하나**(유효 기간 = 보이되 시점 아님).
    /// 폴백은 `uses`와 같다 — 정의 없는 분류는 전부 시점으로 쓴다(사람이 적은 날짜를 조용히 죽이지 않는다).
    public static func schedules(_ key: String?, _ detail: Detail) -> Bool {
        spec(key)?.schedules(detail) ?? true
    }

    /// 이 분류의 **유효 기간 칸**. 정보 = `.resurface`. 없으면 nil(유효 기간 개념이 없는 분류·미분류).
    public static func validUntil(_ key: String?) -> Detail? {
        spec(key)?.validUntil
    }
}
