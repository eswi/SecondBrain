import XCTest
@testable import SecondBrainCore

/// ★ **「결정을 지키는 시험」**(`CLAUDE.md` 「시험을 쓰는 법」).
///
/// ① **무슨 결정인가** — 해시태그 필터(2026-09-22 사용자 · `docs/native/tag-filter-design.md` §1·§2):
///    **중복 선택**(하나라도 가진 기억이 걸린다 = OR) · 맨 끝 **「태그 없음」**(태그가 하나도 없는 기억) ·
///    **「역선택」**(걸린 기억을 숨기고 안 걸린 기억을 보인다 = 정확히 여집합) · 나열하는 태그는 **필터 전 목록**에서.
/// ② **사실** — `TagFilter.matches`는 활성이 아니면 전부 참이고, 활성이면 OR 판정, 역선택이면 그 부정이다.
/// ③ **깨지면 무엇을 의심하나** — 구현이 아니라 **누가 결정을 바꿨나.**
///    - 1이 깨졌다 → OR을 AND로 바꿨다(그러면 「태그 없음」과 태그를 함께 고르는 것이 뜻을 잃는다 · 설계 §2 4번).
///    - 3이 깨졌다 → 역선택이 여집합이 아니게 됐다(「선택되지 않은 기억들을 보이게」가 결정이다).
///    - 4가 깨졌다 → 고른 것이 없을 때 무언가를 숨기게 됐다 — 「닫기」가 「취소」가 아닌데(§2 9번) 빈 필터가 목록을 줄이면 안 된다.
final class TagFilterTests: XCTestCase {

    private func item(_ id: String, tags: [String]) -> ResolvedItem {
        var fields: [String: String] = [:]
        for t in tags { fields[HashTag.key(HashTag.newId())] = t }
        return ResolvedItem(id: id, fields: fields, deleted: false, confirmed: true, createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
    }
    private var items: [ResolvedItem] {
        [item("a", tags: ["맛집"]), item("b", tags: ["맛집", "서울"]), item("c", tags: ["서울"]), item("d", tags: [])]
    }

    // MARK: 1) 중복 선택 = 하나라도 가진 기억 (OR)
    func testMultiSelect_isOr() {
        var f = TagFilter(); f.toggle("맛집"); f.toggle("서울")
        XCTAssertEqual(f.apply(items).map(\.id), ["a", "b", "c"])
        f.toggle("서울")   // 다시 누르면 빠진다
        XCTAssertEqual(f.apply(items).map(\.id), ["a", "b"])
    }

    // MARK: 2) 「태그 없음」 = 태그가 하나도 없는 기억 · 태그와 함께 고를 수 있다
    func testUntagged_aloneAndWithTag() {
        var f = TagFilter(includesUntagged: true)
        XCTAssertEqual(f.apply(items).map(\.id), ["d"])
        f.toggle("서울")
        XCTAssertEqual(f.apply(items).map(\.id), ["b", "c", "d"])
    }

    // MARK: 3) 「역선택」 = 정확히 여집합 (합치면 전부 · 겹침 없음)
    func testInverted_isExactComplement() {
        var f = TagFilter(selected: ["맛집"], includesUntagged: true)
        let on = f.apply(items).map(\.id)
        f.inverted = true
        let off = f.apply(items).map(\.id)
        XCTAssertEqual(on, ["a", "b", "d"])
        XCTAssertEqual(off, ["c"])
        XCTAssertEqual(Set(on).union(off), Set(items.map(\.id)))
        XCTAssertTrue(Set(on).isDisjoint(with: off))
    }

    // MARK: 4) 고른 것이 없으면 전부 — 역선택만 켜져 있어도 전부 (「닫기」는 취소가 아니고, 빈 필터는 목록을 줄이지 않는다)
    func testInactive_passesEverything() {
        XCTAssertFalse(TagFilter().isActive)
        XCTAssertEqual(TagFilter().apply(items).count, 4)
        XCTAssertEqual(TagFilter(inverted: true).apply(items).count, 4)
    }

    // MARK: 5) 나열 = 필터 전 목록의 태그 · 중복 제거 · 정렬 · 지운 태그(빈 값)는 없다
    func testAvailable_uniqueSortedNoEmpty() {
        var withDeleted = items
        var f = withDeleted[0].fields; f[HashTag.key(HashTag.newId())] = ""   // 지운 태그
        withDeleted[0] = ResolvedItem(id: "a", fields: f, deleted: false, confirmed: true, createdHLC: HLC(wallMillis: 1, counter: 0, deviceId: "t"))
        XCTAssertEqual(TagFilter.available(in: withDeleted), ["맛집", "서울"])
    }

    // MARK: 6) 화면에 없는 태그는 접힌다 — 보이지 않는 필터에 갇히지 않게
    func testPruned_dropsStaleKeepsRest() {
        let f = TagFilter(selected: ["맛집", "사라진태그"], includesUntagged: true, inverted: true)
        let p = f.pruned(to: ["맛집", "서울"])
        XCTAssertEqual(p.selected, ["맛집"])
        XCTAssertTrue(p.includesUntagged); XCTAssertTrue(p.inverted)
        XCTAssertFalse(TagFilter(selected: ["사라진태그"]).pruned(to: []).isActive)
    }

    // MARK: 7) 제목의 숫자 셋 = 전체 · 선택 · 그 외 — 합이 맞고, 「역선택」을 켜도 셋은 그대로다 (2026-09-22 사용자 · 설계 §7)
    //    깨졌다면 → 누군가 「선택」을 「보이는 것」으로 바꿨다(그러면 역선택을 켤 때 선택 수가 뒤집혀 제목이 거짓말을 한다).
    func testCounts_totalSelectedRest_ignoreInversion() {
        var f = TagFilter(selected: ["맛집"], includesUntagged: true)
        var c = f.counts(in: items)
        XCTAssertEqual(c.total, 4); XCTAssertEqual(c.selected, 3); XCTAssertEqual(c.rest, 1)
        f.inverted = true
        c = f.counts(in: items)
        XCTAssertEqual(c.selected, 3); XCTAssertEqual(c.rest, 1)   // 보이는 것은 1이지만 선택은 3
        let none = TagFilter(inverted: true).counts(in: items)
        XCTAssertEqual(none.total, 4); XCTAssertEqual(none.selected, 0); XCTAssertEqual(none.rest, 4)
    }
}
