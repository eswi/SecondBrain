import Foundation

/// 여러 이벤트를 하나의 받은함 상태로 해소한 결과.
/// (Hashable — 상세 화면 navigationDestination 값으로 사용.)
public struct ResolvedItem: Sendable, Equatable, Hashable {
    public let id: String
    public let fields: [String: String]   // per-field LWW로 해소된 콘텐츠 필드(제어필드 deleted/confirmed 제외)
    public let deleted: Bool
    /// 확정 여부. **단방향(grow-only)** — LWW가 아니라 OR-머지로 계산한다(edit-policy.md §3).
    /// 이벤트 중 하나라도 confirmed=true면 영원히 true. 확정 후의 편집·HLC 순서와 무관.
    public let confirmed: Bool
    public let createdHLC: HLC            // 최소 HLC(정렬·"캡처 시점"용)

    public var raw: String? { fields["raw"] }
    public var type: String? { fields["type"] }
    public var due: String? { fields["due"] }
    public var resurface: String? { fields["resurface"] }
    public var status: String? { fields["status"] }
    public var source: String? { fields["source"] }
    public var date: String? { fields["date"] }
    public var time: String? { fields["time"] }

    /// 변경 한 묶음을 **필드별 LWW 한 번**으로 겹친 결과. `edit` 이벤트가 반영된 뒤의 모습과 같다.
    /// **빈 문자열은 값 지움**(앱의 `set k=` 규약 — `MergeEngine.merge`의 처리와 같다).
    /// 제어 필드(`deleted`·`confirmed`)와 `createdHLC`는 안 건드린다 — 편집으로 바뀌는 값이 아니다.
    ///
    /// 쓰임: 저장 **전에** "저장되면 어떤 모습인가"를 알아야 하는 자리
    /// (규칙 1 최종 검사 · 상세 화면의 기준선 갱신 — 2026-08-06 `가`).
    public func applying(_ changes: [String: String]) -> ResolvedItem {
        var f = fields
        for (k, v) in changes { if v.isEmpty { f.removeValue(forKey: k) } else { f[k] = v } }
        return ResolvedItem(id: id, fields: f, deleted: deleted, confirmed: confirmed, createdHLC: createdHLC)
    }
}

public struct MergeResult: Sendable, Equatable {
    public let live: [ResolvedItem]       // 화면에 보일 항목(삭제 아님)
    public let deleted: [ResolvedItem]    // tombstone(복구 UI용)

    public func item(_ id: String) -> ResolvedItem? {
        live.first { $0.id == id } ?? deleted.first { $0.id == id }
    }
}

/// 합치기 엔진(설계 `docs/native/merge-design.md`). 순수 함수 — 결정적·순서무관·멱등.
public enum MergeEngine {
    public static func merge(_ events: [Event]) -> MergeResult {
        var byId: [String: [Event]] = [:]
        for e in events { byId[e.id, default: []].append(e) }

        var live: [ResolvedItem] = []
        var deleted: [ResolvedItem] = []

        for (id, evs) in byId {
            var resolved: [String: String] = [:]   // 필드 → 값
            var bestHLC: [String: HLC] = [:]        // 필드 → 그 값을 세팅한 최대 HLC
            var maxEvent = evs[0]                   // 항목 전체 최고 HLC 이벤트(삭제 판정용)
            var createdHLC = evs[0].hlc             // 최소 HLC
            var confirmed = false                   // OR-머지(grow-only): 하나라도 true면 영원히 true

            for e in evs {
                if e.hlc > maxEvent.hlc { maxEvent = e }
                if e.hlc < createdHLC { createdHLC = e.hlc }
                if e.fields["confirmed"] == "true" { confirmed = true }   // HLC 무관·단방향
                for (k, v) in e.fields {
                    // per-field LWW: 엄격한 > 이므로 순서무관·멱등(동일 HLC는 덮지 않음)
                    if let h = bestHLC[k] {
                        if e.hlc > h { resolved[k] = v; bestHLC[k] = e.hlc }
                    } else {
                        resolved[k] = v; bestHLC[k] = e.hlc
                    }
                }
            }

            // 삭제 판정(P1): 최고 HLC 이벤트가 deleted=true 면 숨김. 콘텐츠 편집/undelete가 최고면 live(부활).
            let isDeleted = (maxEvent.fields["deleted"] == "true")

            var userFields = resolved
            userFields["deleted"] = nil     // 제어필드는 사용자 필드에서 제거
            userFields["confirmed"] = nil   // confirmed는 별도 OR-머지 값으로 노출(LWW 대상 아님)

            let item = ResolvedItem(id: id, fields: userFields, deleted: isDeleted,
                                    confirmed: confirmed, createdHLC: createdHLC)
            if isDeleted { deleted.append(item) } else { live.append(item) }
        }

        // 결정적 정렬: 최신 캡처 우선, 동률이면 id
        let sorter: (ResolvedItem, ResolvedItem) -> Bool = { a, b in
            if a.createdHLC != b.createdHLC { return a.createdHLC > b.createdHLC }
            return a.id < b.id
        }
        return MergeResult(live: live.sorted(by: sorter), deleted: deleted.sorted(by: sorter))
    }

    /// 편의: 레거시 v0 항목 배열을 이벤트로 바꿔 병합.
    public static func mergeLegacy(_ items: [InboxItem]) -> MergeResult {
        merge(items.enumerated().map { Event.fromLegacy($1, index: $0) })
    }
}
