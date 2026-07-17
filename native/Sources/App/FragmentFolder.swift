import Foundation

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
    private static func withFolder<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let folder = resolve() else { return nil }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        return try body(folder)
    }

    // MARK: 읽기 (파일 조율 + iCloud 다운로드)

    /// 폴더의 `inbox*.md`를 모두 (파일명, 내용)으로. iCloud 미다운로드 파일은 당겨오기 시도.
    static func readFragments() -> [(name: String, text: String)] {
        (withFolder { folder -> [(name: String, text: String)] in
            let fm = FileManager.default
            guard let entries = try? fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil) else { return [] }
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
            return out
        }) ?? []
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
