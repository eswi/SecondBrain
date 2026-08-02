import XCTest
@testable import SecondBrainCore

/// Stage 0 그물 (양력 반복 착수 전) — **기존 완료 동작을 고정한다.**
/// Stage 3(완료 분기)이 유일한 파괴적 지점이라, 그 전에
/// **"기존 항목을 완료하면 살아있는 목록에서 빠지고 보관함(완료)으로 간다"** 를 명시적으로 남긴다.
///
/// 라우팅 정본 = `InboxModel.resolve()` (`Sources/App/InboxModel.swift:193-198`):
///   active      = live where type != "discard"
///   liveNonDone = active where status != "done"   (살아있음: 지금 챙길 것·살아있는 기억·알림의 소스)
///   doneItems   = active where status == "done"   (보관함 "완료된 기억")
///   trashed     = deleted + live where type == "discard"
/// 이 테스트는 그 계약을 Core 데이터 층에서 고정한다.
/// **Stage 3 규약:** 반복 완료는 이 필터를 건드리지 않는다 — 비반복은 여전히 `status=done`→보관함이어야 하고,
/// 반복만 별도 경로(마지막 완료 시점 기록, status 무변경)로 분기한다.
final class CompletionRoutingTests: XCTestCase {

    private func h(_ w: Int64, _ c: Int, _ d: String) -> HLC { HLC(wallMillis: w, counter: c, deviceId: d) }

    /// `InboxModel.resolve()`의 라우팅을 그대로 미러링(정본 = InboxModel:193-198).
    private func route(_ r: MergeResult) -> (live: [ResolvedItem], done: [ResolvedItem], trashed: [ResolvedItem]) {
        let active = r.live.filter { $0.type != "discard" }
        return (active.filter { $0.status != "done" },
                active.filter { $0.status == "done" },
                r.deleted + r.live.filter { $0.type == "discard" })
    }

    // ★ 사용자 명시 요청: 완료하면 살아있는 목록에서 빠지고 보관함으로 간다.
    func testComplete_leavesLive_goesToDone() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "2026-08-02", time: "09:00", source: "voice", raw: "약속", extra: ["type": "info-action"]),
            .edit(id: "a", hlc: h(2, 0, "i"), ["status": "done"]),   // markDone()과 동일한 이벤트
        ])
        let p = route(r)
        XCTAssertFalse(p.live.contains { $0.id == "a" }, "완료 항목은 살아있는 목록에 없어야 한다")
        XCTAssertTrue(p.done.contains { $0.id == "a" }, "완료 항목은 보관함(완료)에 있어야 한다")
    }

    // 되돌릴 수 있다: 더 큰 HLC로 status=open → 다시 살아있음(restore와 동일 경로).
    func testComplete_reversible_restore() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "2026-08-02", time: "09:00", source: "voice", raw: "약속"),
            .edit(id: "a", hlc: h(2, 0, "i"), ["status": "done"]),
            .edit(id: "a", hlc: h(3, 0, "i"), ["status": "open"]),   // restore()
        ])
        let p = route(r)
        XCTAssertTrue(p.live.contains { $0.id == "a" }, "되돌리면 다시 살아있어야")
        XCTAssertFalse(p.done.contains { $0.id == "a" })
        XCTAssertEqual(r.item("a")?.status, "open")
    }

    // status 없음/open은 살아있음(완료 아님).
    func testOpenOrNoStatus_isLive() {
        let r = MergeEngine.merge([
            .create(id: "open", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x", extra: ["status": "open"]),
            .create(id: "none", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "y"),
        ])
        let p = route(r)
        XCTAssertEqual(Set(p.live.map { $0.id }), ["open", "none"])
        XCTAssertTrue(p.done.isEmpty)
    }

    // discard는 휴지통(살아있음도 완료도 아님) — 기존 특례 보존.
    func testDiscard_isTrashed_notLiveNotDone() {
        let r = MergeEngine.merge([
            .create(id: "a", hlc: h(1, 0, "i"), date: "d", time: "t", source: "voice", raw: "x", extra: ["type": "discard"]),
        ])
        let p = route(r)
        XCTAssertFalse(p.live.contains { $0.id == "a" })
        XCTAssertFalse(p.done.contains { $0.id == "a" })
        XCTAssertTrue(p.trashed.contains { $0.id == "a" })
    }
}
