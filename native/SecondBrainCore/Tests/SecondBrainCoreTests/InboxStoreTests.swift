import XCTest
@testable import SecondBrainCore

final class InboxStoreTests: XCTestCase {

    // 두 기기 조각을 텍스트로 병합: 크로스 기기 생성·수정·삭제가 하나의 받은함으로.
    func testMergeTwoFragmentTexts() {
        let iphone = """
        - 2026-07-16 09:00 | voice | 우유 사오기
          id: p1
          hlc: 100.0.iphone
          type: info-action
        - 2026-07-16 09:05 | voice | 김대표 만나기
          id: p2
          hlc: 101.0.iphone
          type: promise
        """
        let mac = """
        - 2026-07-16 10:00 | doc | 이사 계획 정리
          id: m1
          hlc: 120.0.mac
          type: info-action
          due: 2026-07-19
        @ 121.0.mac | p1 | set due=2026-07-17
        @ 130.0.mac | p2 | delete
        """
        let r = InboxStore.merge(fragmentTexts: [iphone, mac])
        // p1: 아이폰 생성 + 맥이 due 편집 → 병합
        XCTAssertEqual(r.item("p1")?.due, "2026-07-17")
        XCTAssertEqual(r.item("p1")?.type, "info-action")
        // m1: 맥 생성
        XCTAssertEqual(r.item("m1")?.type, "info-action")
        // p2: 맥이 삭제 → 숨김
        XCTAssertEqual(r.item("p2")?.deleted, true)
        XCTAssertEqual(r.live.count, 2)      // p1, m1
        XCTAssertEqual(r.deleted.count, 1)   // p2
    }

    // 디렉터리 로드: 임시 폴더에 조각 2개 써두고 읽어 병합.
    func testLoadDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "- 2026-07-16 09:00 | voice | 아이폰 항목\n  id: p1\n  hlc: 100.0.iphone\n  type: idea\n"
            .write(to: dir.appendingPathComponent("inbox-iphone.md"), atomically: true, encoding: .utf8)
        try "@ 200.0.mac | p1 | set type=discard\n- 2026-07-16 10:00 | doc | 맥 항목\n  id: m1\n  hlc: 120.0.mac\n"
            .write(to: dir.appendingPathComponent("inbox-mac.md"), atomically: true, encoding: .utf8)
        // inbox 아닌 파일은 무시돼야 함
        try "무시".write(to: dir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        let (result, files) = InboxStore.loadDirectory(dir)
        XCTAssertEqual(files.sorted(), ["inbox-iphone.md", "inbox-mac.md"])
        XCTAssertEqual(result.item("p1")?.type, "discard")   // 맥 편집 반영
        XCTAssertNotNil(result.item("m1"))
        XCTAssertEqual(result.live.count, 2)
    }
}
