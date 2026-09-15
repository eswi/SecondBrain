import XCTest
@testable import SecondBrainCore

/// 수집 초안(「쓰다 만 기억」) 저장소 — `docs/native/capture-draft-design.md`.
/// ★ **지키는 결정:** ① 빈 초안은 남지 않는다 ② 최근 것이 앞 ③ 지우면 사진 폴더도 함께 사라진다(고아 없음).
/// 깨지면 구현이 아니라 그 결정을 먼저 본다.
final class CaptureDraftTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sb-draft-test-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testRoundTrip_andOrderNewestFirst() throws {
        let a = CaptureDraft(id: "A", text: "첫째", createdAt: 10, updatedAt: 10)
        let b = CaptureDraft(id: "B", text: "둘째", urls: ["https://example.com/"], createdAt: 20, updatedAt: 30)
        try CaptureDraftStore.write(a, in: dir)
        try CaptureDraftStore.write(b, in: dir)
        let got = CaptureDraftStore.list(in: dir)
        XCTAssertEqual(got.map(\.id), ["B", "A"], "최근에 고친 것이 앞")
        XCTAssertEqual(got.first, b)
    }

    func testBlankDraft_isNotWritten_andDeletesExisting() throws {
        var d = CaptureDraft(id: "X", text: "글", createdAt: 1, updatedAt: 1)
        try CaptureDraftStore.write(d, in: dir)
        XCTAssertEqual(CaptureDraftStore.list(in: dir).count, 1)
        d.text = "   \n"   // 전부 지웠다
        XCTAssertTrue(d.isBlank)
        try CaptureDraftStore.write(d, in: dir)
        XCTAssertTrue(CaptureDraftStore.list(in: dir).isEmpty, "빈 초안은 목록에 남지 않는다")
        // 사진만 있어도 빈 것이 아니다
        XCTAssertFalse(CaptureDraft(id: "P", photos: ["p.jpg"], createdAt: 1, updatedAt: 1).isBlank)
    }

    func testDelete_removesPhotoFolderToo() throws {
        let d = CaptureDraft(id: "D", text: "사진 있음", photos: ["a.jpg"], createdAt: 1, updatedAt: 1)
        try CaptureDraftStore.write(d, in: dir)
        let folder = CaptureDraftStore.folder(id: "D", in: dir)
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("a.jpg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        CaptureDraftStore.delete(id: "D", in: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "사진 폴더도 함께 사라진다")
        XCTAssertTrue(CaptureDraftStore.list(in: dir).isEmpty)
        CaptureDraftStore.delete(id: "D", in: dir)   // 없어도 조용하다
    }

    func testList_skipsGarbage() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("junk.json"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("note.txt"))
        try CaptureDraftStore.write(CaptureDraft(id: "OK", text: "멀쩡", createdAt: 1, updatedAt: 1), in: dir)
        XCTAssertEqual(CaptureDraftStore.list(in: dir).map(\.id), ["OK"])
    }
}
