import Foundation

/// 자료 포인터의 꼴 — **자료마다 별도 필드**(2026-08-23 사용자 결정).
/// 결정·세 안의 대가: `docs/native/media-expansion-design.md` **§3-W**(요약) · **§3-V-1**(안 셋).
///
/// ## 왜 별도 필드인가 — 병합에서 자료가 사라지지 않게
/// 병합은 **항목별·필드별 LWW**다(`merge-design.md` §3 — *"두 기기가 **다른 필드** 동시 편집 → 둘 다
/// 반영(무손실). **같은 필드** 충돌만 HLC 최신 승"*).
/// - ⛔ 한 필드에 **쉼표 목록**(`photo: a.jpg, b.jpg`)을 담으면 두 기기가 각각 한 장씩 붙였을 때
///   **같은 필드**라서 한쪽 목록이 통째로 진다 — **자료가 사라진다**(파일은 남고 포인터만 없어져 조용하다).
/// - ✅ 자료마다 **다른 필드**면 언제나 「다른 필드」 경로라 **둘 다 산다.**
///   그래서 이 꼴은 `MergeEngine`·`merge-design.md`를 **한 줄도 안 건드린다.**
///
/// ## ⛔ 자료 id는 **소문자 16진 32자(하이픈 없음)**다 — 취향이 아니라 파서 제약이다
/// 2026-08-23 맥미니 실측(`MediaPointerTests`가 이 사실을 못 박는다):
/// - create 블록·편집 블록의 필드 줄은 키를 `[A-Za-z0-9_.]+`로만 읽는다(`EventLog.parse`의 `fieldRe`)
///   → **키에 하이픈이 있으면 그 줄이 조용히 스킵된다**(값이 사라지고 아무 신호가 없다).
/// - 같은 경로가 키를 `lowercased()`한다 → **대문자가 있으면 왕복 때 키가 달라진다.**
/// - ⚠️ **`UUID().uuidString`은 대문자+하이픈**이다(항목 id가 그 꼴이다) — **그대로 키에 쓰면 안 된다.**
///   그래서 `newAssetId()`가 있다. 항목 id는 필드의 **값**이라 이 제약에 안 걸린다.
///
/// ⚠️ 안 고른 길: **파서의 charset을 넓혀 하이픈을 허용하는 것.** 왕복 계약(`EventWriter`·`EventLog`)과
/// 레거시 파일을 건드리므로, **키 꼴을 좁혀 위험을 없애는 쪽**을 골랐다.
public enum MediaPointer {

    /// 종류 접두어 = 필드 이름의 앞부분. **옛 단일 포인터 필드와 같은 말을 쓴다**(`audio`·`photo`).
    ///
    /// ## ★ `url`은 **파일이 아닌 첫 종류**다 (2026-08-24 사용자 결정 · 설계 §3-Z)
    /// 사진·음성은 **값이 파일 이름**이고 조회가 그 이름으로 파일을 찾는다(§3-X).
    /// **URL은 파일이 없다 — 값이 자료 자신이다.** 그래서 「포인터 값 = 파일 이름」이 여기서 갈린다
    /// (`CLAUDE.md` 정본 훑기 규칙 2의 신호 ③ — *"「A 무관」이 「A에 따라 갈린다」가 된다"*).
    /// **갈리는 자리를 `fileKind` 한 곳으로 모았다** — 파일 층(`MediaKind`)에는 `url`이 아예 없어서
    /// iCloud 업로드·받아오기·들여오기가 **URL을 그냥 못 본다**(막는 코드가 필요 없다).
    ///
    /// ⏸ 아직 안 정한 종류: **동영상**(⛔ 용량 때문에 맨 뒤로 미뤘다 — `CLAUDE.md` 「미뤄둔 것」) ·
    /// PDF · 기타. **기타는 「한 종류 = 확장자 하나」가 깨지는 자리다**(동영상의 어려움 ②와 같다).
    public enum Kind: String, CaseIterable, Sendable {
        case audio
        case photo
        case url

        /// **파일 층의 종류 — URL은 nil이다.** 「이 종류에 파일이 있나」는 여기서만 갈린다.
        public var fileKind: MediaKind? {
            switch self {
            case .audio: return .audio
            case .photo: return .photo
            case .url:   return nil
            }
        }

        /// 포인터 **값이 파일 이름인가.** `false`면 **값이 자료 자신**이다(URL 문자열).
        public var valueIsFilename: Bool { fileKind != nil }

        /// 파일 확장자 — 지금 앱이 저장하는 것과 같다(`AudioStore`·`PhotoStore`).
        /// ⚠️ **파일이 아닌 종류는 nil이다**(2026-08-24 — 옛 서술: *"파일 확장자"*로 늘 값이 있었다).
        public var ext: String? { fileKind?.ext }
    }

    /// 새 자료 id — **소문자 16진 32자, 하이픈 없음**(위 제약).
    public static func newAssetId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// 이 id를 필드 이름에 써도 되나 — 소문자 16진만.
    public static func isValidAssetId(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// 필드 이름 조립 — `photo.<자료id>`.
    public static func key(_ kind: Kind, _ assetId: String) -> String {
        "\(kind.rawValue).\(assetId)"
    }

    /// 필드 이름 해석. 포인터 필드가 아니면 nil.
    /// **옛 단일 필드**(`photo`·`audio`)는 `assetId == nil`로 돌려준다 — 옛 파일은 이름을 안 바꾼다(§6).
    public static func parse(_ key: String) -> (kind: Kind, assetId: String?)? {
        if let k = Kind(rawValue: key) { return (k, nil) }
        guard let dot = key.firstIndex(of: ".") else { return nil }
        guard let k = Kind(rawValue: String(key[key.startIndex..<dot])) else { return nil }
        let id = String(key[key.index(after: dot)...])
        guard isValidAssetId(id) else { return nil }
        return (k, id)
    }

    /// 한 종류의 포인터 전부 — **옛 단일 필드와 새 필드를 함께** 읽는다(공존).
    /// 순서는 **결정적**이려고 정한 것뿐이다(옛 단일 → 자료 id 오름차순).
    /// ⛔ **화면에 보이는 순서 결정이 아니다** — 그것은 아직 안 정했다(뷰어의 `<` `>` · §0-3).
    public static func pointers(_ kind: Kind, in fields: [String: String]) -> [(assetId: String?, value: String)] {
        var out: [(assetId: String?, value: String)] = []
        if let v = fields[kind.rawValue], !v.isEmpty { out.append((nil, v)) }
        let extras = fields.compactMap { (k, v) -> (String, String)? in
            guard !v.isEmpty, let p = parse(k), p.kind == kind, let id = p.assetId else { return nil }
            return (id, v)
        }
        out.append(contentsOf: extras.sorted { $0.0 < $1.0 }.map { (assetId: Optional($0.0), value: $0.1) })
        return out
    }

    // MARK: - 파일명 (B · 2026-08-23 사용자 결정 ㉰)

    /// 자료 파일 이름 = **`<항목id>-<자료id>.<확장자>`**.
    /// 결정·안 고른 것: `docs/native/media-expansion-design.md` **§3-W-6** · 안 셋은 **§3-V-2**.
    ///
    /// **왜 항목 id를 앞에 두나:** 폴더를 사람이 읽을 수 있게 — **파일만 보고 어느 기억 것인지 알고**,
    /// 같은 기억의 자료가 **한자리에 모여 정렬**되고, **고아 판정**(자료 삭제 · 뜻 ③)을 파일명만으로도 할 수 있다.
    /// (이 저장소는 실데이터를 손으로 훑는 일이 많다 — 평문·grep 가능이 자산이다.)
    /// **왜 자료 id를 뒤에 두나:** **충돌이 원천적으로 없다.** ⛔ 안 고른 `<항목id>-<n>`은 두 기기가
    /// 동시에 붙이면 **같은 n을 만들어 한 파일이 다른 파일을 덮는다**(포인터는 살아도 파일이 사라진다).
    ///
    /// ⚠️ 옛 파일은 **`<항목id>.<확장자>`이고 이름을 안 바꾼다**(§6) — 그래서 `parseFilename`이 둘을 가른다.
    /// ⚠️ **받는 것은 파일 층의 종류(`MediaKind`)다**(2026-08-24) — 그래서 **URL로는 부를 수 없다.**
    /// 파일이 없는 종류에 파일 이름을 만드는 길을 **컴파일 단계에서 막았다**(런타임 검사가 아니다).
    public static func filename(_ kind: MediaKind, itemId: String, assetId: String) -> String {
        "\(itemId)-\(assetId).\(kind.ext)"
    }

    /// 파일 이름 해석 — 새 꼴이면 `assetId`가 있고, **옛 단일 파일이면 `assetId == nil`**.
    ///
    /// ★ **가르는 근거:** 항목 id(`UUID().uuidString`)에는 **하이픈이 있고**, 자료 id에는 **없다.**
    /// 그래서 **마지막 하이픈 뒤**가 「소문자 16진」이면 그것이 자료 id다 — 항목 id 쪽은 그 꼴이 될 수 없다.
    public static func parseFilename(_ name: String) -> (itemId: String, assetId: String?)? {
        guard let dot = name.lastIndex(of: ".") else { return nil }
        let base = String(name[name.startIndex..<dot])
        guard !base.isEmpty else { return nil }
        if let dash = base.lastIndex(of: "-") {
            let tail = String(base[base.index(after: dash)...])
            let head = String(base[base.startIndex..<dash])
            if !head.isEmpty, isValidAssetId(tail), tail.count == 32 {
                return (head, tail)     // 새 꼴
            }
        }
        return (base, nil)              // 옛 단일 파일
    }
}
