import Foundation

/// **해시태그 — 분류 안의 가벼운 세분**(`memory-philosophy.md` §7-1 · 저장·표시는 `docs/native/hashtag-design.md` · 2026-09-17 사용자 결정).
///
/// ## 꼴 — **태그마다 필드 하나** `tag.<id>` = 태그 글 (결정 1 ㉡)
/// 자료 포인터(`MediaPointer`)와 같은 이유다: 병합이 **항목별·필드별 LWW**라(`merge-design.md` §3) 한 필드에 쉼표 목록을 담으면
/// 두 기기가 각자 붙인 태그 중 한쪽 목록이 통째로 진다. 필드가 다르면 둘 다 산다(`HashTagTests` 1·2).
///
/// ## ⛔ 왜 `tag.<태그글>`이 아닌가 — 파서 제약
/// 필드 이름은 `[A-Za-z0-9_.]+`로만 읽히고 소문자로 접힌다(`MediaPointer` 머리주석). 태그는 **한글·안 공백·대소문자 구분**(결정 4)이라
/// 이름에 못 들어간다. **값**이면 전부 무손실이다 — 공백이 있으면 `EventWriter`가 스스로 `edit` 블록(JSON)으로 보낸다.
///
/// **지우기 = 빈 값** · **고치기 = 같은 id에 새 값.** 빈 값은 `tags(in:)`가 거른다.
public enum HashTag {
    /// 필드 이름 접두어. ⚠️ `MediaPointer.Kind`에 `tag`가 없으므로 그쪽 `parse`는 이 필드를 nil로 본다(시험 6).
    public static let prefix = "tag."

    /// 한 태그 — `id`는 필드 이름의 뒷부분, `text`는 값(다듬어진 글).
    public struct Tag: Equatable, Hashable, Sendable {
        public let id: String
        public let text: String
        public init(id: String, text: String) { self.id = id; self.text = text }
        /// 화면 꼴 — `#` + 글. 저장 값에는 `#`이 없다.
        public var display: String { HashTag.display(text) }
    }

    /// 새 태그 id — 자료 id와 같은 꼴(소문자 16진 32자 · 하이픈 없음).
    public static func newId() -> String { MediaPointer.newAssetId() }

    /// 필드 이름 조립 — `tag.<id>`.
    public static func key(_ id: String) -> String { prefix + id }

    /// 필드 이름 해석 — 태그 필드면 id, 아니면 nil. id 꼴이 아니면(대문자·하이픈·빈 것) nil.
    public static func parseKey(_ key: String) -> String? {
        guard key.hasPrefix(prefix) else { return nil }
        let id = String(key.dropFirst(prefix.count))
        return MediaPointer.isValidAssetId(id) ? id : nil
    }

    /// **다듬기(결정 4)** — 앞뒤 공백·줄바꿈 제거 → 앞의 `#`들을 뗀다 → 안의 줄바꿈은 공백으로 → 다시 앞뒤 제거.
    /// **안의 공백·대소문자는 그대로.** 비면 nil(붙일 것이 없다).
    public static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("#") { s.removeFirst() }
        s = s.components(separatedBy: .newlines).joined(separator: " ")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// 화면 꼴 — `#` + 글.
    public static func display(_ text: String) -> String { "#" + text }

    /// 이 항목의 태그 전부 — **빈 값(지운 것)은 거른다.** 순서 = 글의 정렬(`localizedStandardCompare`) · 같은 글이면 id 순.
    /// ⚠️ 붙인 순서가 아니다 — 필드에는 그 정보가 없다(설계 §2).
    public static func tags(in fields: [String: String]) -> [Tag] {
        fields.compactMap { (k, v) -> Tag? in
            guard !v.isEmpty, let id = parseKey(k) else { return nil }
            return Tag(id: id, text: v)
        }.sorted { a, b in
            let c = a.text.localizedStandardCompare(b.text)
            return c == .orderedSame ? a.id < b.id : c == .orderedAscending
        }
    }

    /// 이 글이 이미 붙어 있나(대소문자까지 같을 때만 같다 — 결정 4).
    public static func contains(_ text: String, in fields: [String: String]) -> Bool {
        tags(in: fields).contains { $0.text == text }
    }
}

public extension ResolvedItem {
    /// 이 기억의 해시태그(빈 값 제외 · 정렬됨).
    var hashtags: [HashTag.Tag] { HashTag.tags(in: fields) }
}
