import Foundation
import SecondBrainCore

/// 사용자가 고른 **iCloud Drive의 열린 폴더**(예: `iCloud Drive/SecondBrain`)에 대한 접근.
/// 문서 피커로 1회 선택 → **보안 스코프 북마크**로 영속. iCloud entitlement 불필요 → 무료 서명 유지.
/// 조각 파일은 이 폴더에 `inbox-<device>.md`로 두고 기존 `inbox.md`(웹 v0)와 나란히 공존한다.
/// 앱은 이 폴더의 `inbox*.md`를 모두 읽되(레거시 inbox.md 포함), **자기 기기 조각에만 append**한다.
enum FragmentFolder {
    private static let bookmarkKey = "sb_folder_bookmark"

    static var hasFolder: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    // MARK: 북마크 저장/해소

    /// 문서 피커가 준 폴더 URL을 보안 스코프 북마크로 저장.
    static func saveBookmark(for url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let data = try url.bookmarkData(options: [.withSecurityScope],
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let data = try url.bookmarkData(options: [],   // iOS는 피커 URL이 자동 보안스코프
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    /// 저장된 북마크 → URL. stale이면 재저장 시도.
    private static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        #if os(macOS)
        let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        #else
        let url = try? URL(resolvingBookmarkData: data, options: [],
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
        if let url, stale { try? saveBookmark(for: url) }
        return url
    }

    /// 보안 스코프를 열고 폴더 URL로 작업. 폴더 미선택이면 nil.
    ///
    /// ## ⚠️ 스코프는 이 함수가 돌아올 때 닫힌다 — **URL을 내보내지 말 것**
    ///
    /// 돌려받은 URL을 **나중에** 읽는 것은 보장되지 않는다. 그래서 규칙이 하나 있다:
    /// **`body`는 값을 돌려준다 — URL이 아니라 내용·사실·성패를.**
    /// (`read()`는 `String`을, `cloudFacts`는 `Bool` 둘을, `adopt`는 `Bool`을 돌려준다.)
    ///
    /// **2026-08-20에 이 규칙을 어긴 자리 하나를 없앴다** — `MediaCloud.readableURL`이
    /// **iCloud URL을 돌려주고 있었다.** 지금은 `MediaCloud.adopt`가 **스코프 안에서 로컬로 복사**하고,
    /// 화면은 **로컬 URL만** 본다(설계 §2-A C안).
    /// **훑어서 확인했다(2026-08-20): 지금 `withFolder` 호출 일곱 개 중 URL을 내보내는 것은 0개다.**
    static func withFolder<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let folder = resolve() else { return nil }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        return try body(folder)
    }

    // MARK: 읽기 (파일 조율 + iCloud 다운로드)

    /// 폴더의 `inbox*.md`를 모두 (파일명, 내용)으로. iCloud 미다운로드 파일은 당겨오기 시도.
    static func readFragments() -> [(name: String, text: String)] {
        read().fragments
    }

    /// **읽기 + 그 과정에서 드러난 사실**(사양서 §0-A-1). 판정은 Core(`FolderLinkJudge`)가 한다 —
    /// 여기서는 **실제로 시도해 본 결과만** 모은다.
    ///
    /// **옛 구조가 왜 안 됐나:** 화면은 `hasFolder`(= `UserDefaults`에 데이터가 있나)로 판정했는데
    /// 그건 **저장값**이라 "못 연다"를 원리적으로 못 잡는다. 그래서 연결이 끊겨도 안내 화면에
    /// **도달조차 안 하고** 빈 목록이 떴다. **읽어봐야 아는 것을 읽지 않고 판정하고 있었다.**
    ///
    /// 옛 코드가 조용히 삼키던 자리 셋을 여기서 전부 사실로 남긴다:
    /// 북마크 해소(`resolved`) · **보안 스코프 접근**(`accessGranted` — 반환값을 보지도 않았다) ·
    /// 디렉터리 목록(`directoryListed`).
    static func read() -> (fragments: [(name: String, text: String)], status: FolderLink, folderName: String) {
        guard hasFolder else { return ([], .notChosen, "") }
        guard let folder = resolve() else { return ([], .unreachable, "") }
        let name = folder.lastPathComponent

        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return ([], FolderLinkJudge.status(bookmarkExists: true, resolved: true,
                                               accessGranted: accessed, directoryListed: false,
                                               fragmentFiles: 0, readableFiles: 0), name)
        }
        let frags = entries
            .filter { $0.lastPathComponent.hasPrefix("inbox") && $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var out: [(name: String, text: String)] = []
        let coord = NSFileCoordinator()
        for u in frags {
            try? fm.startDownloadingUbiquitousItem(at: u)   // iCloud 원격만 있으면 당겨오기
            var cerr: NSError?
            coord.coordinate(readingItemAt: u, options: [], error: &cerr) { r in
                if let t = try? String(contentsOf: r, encoding: .utf8) {
                    out.append((name: u.lastPathComponent, text: t))
                }
            }
        }
        // 목록엔 잡혔는데 내용이 하나도 안 읽히면 = iCloud에서 아직 안 내려온 것(`.downloading`).
        // **새 기기에서 가장 흔한 경로**이고, 이 구분이 없으면 "비었다"와 같아진다.
        let status = FolderLinkJudge.status(bookmarkExists: true, resolved: true,
                                            accessGranted: accessed, directoryListed: true,
                                            fragmentFiles: frags.count, readableFiles: out.count)
        return (out, status, name)
    }

    // MARK: 쓰기 (append-only, 조율)

    enum WriteError: Error { case noFolder }

    /// 이 기기 조각 `inbox-<deviceId>.md` 끝에 한 줄/블록 append. **inbox.md는 절대 안 건드림.**
    static func appendLine(_ line: String, deviceId: String) throws {
        let done: Void? = try withFolder { folder in
            let target = folder.appendingPathComponent("inbox-\(deviceId).md")
            let fm = FileManager.default
            let coord = NSFileCoordinator()
            var cerr: NSError?
            var inner: Error?
            coord.coordinate(writingItemAt: target, options: [], error: &cerr) { w in
                do {
                    let data = Data(line.utf8)
                    if fm.fileExists(atPath: w.path) {
                        let h = try FileHandle(forWritingTo: w)
                        defer { try? h.close() }
                        try h.seekToEnd()
                        try h.write(contentsOf: data)
                    } else {
                        try data.write(to: w, options: .atomic)
                    }
                } catch { inner = error }
            }
            if let e = inner ?? cerr { throw e }
        }
        if done == nil { throw WriteError.noFolder }
    }
}
