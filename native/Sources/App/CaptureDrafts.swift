import Foundation
import SecondBrainCore

/// **수집 초안(「쓰다 만 기억」)의 자리** — 기기 로컬 `Application Support/SecondBrain/capture-drafts/`.
///
/// ⛔ **iCloud 폴더가 아니다** — 초안은 기억이 아니고(설계 `capture-draft-design.md` §1) 병합 대상도 아니다.
/// 그래서 `PhotoStore`·`AudioStore`의 로컬 디렉터리와 **같은 뿌리**(`Application Support/SecondBrain/`)에 둔다.
/// **읽기·쓰기는 Core `CaptureDraftStore`**가 하고, 여기는 **디렉터리 하나**만 안다.
enum CaptureDrafts {
    static func dir() -> URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true) else { return nil }
        let d = base.appendingPathComponent("SecondBrain/capture-drafts", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func list() -> [CaptureDraft] { dir().map { CaptureDraftStore.list(in: $0) } ?? [] }
    static func write(_ d: CaptureDraft) { if let dir = dir() { try? CaptureDraftStore.write(d, in: dir) } }
    static func delete(id: String) { if let dir = dir() { CaptureDraftStore.delete(id: id, in: dir) } }
    /// 이 초안의 사진 폴더(없으면 만든다). 없는 디렉터리면 nil.
    static func folder(id: String) -> URL? { dir().map { CaptureDraftStore.folder(id: id, in: $0) } }
    /// 초안에 적힌 파일 이름 → **지금 있는** 파일 URL만. 없는 것은 로그에 남긴다(`draft.log`).
    static func photoURLs(_ d: CaptureDraft) -> [URL] {
        guard let f = folder(id: d.id) else { log("restore \(d.id.prefix(8)) — 폴더 없음"); return [] }
        let all = d.photos.map { f.appendingPathComponent($0) }
        let have = all.filter { FileManager.default.fileExists(atPath: $0.path) }
        log("restore \(d.id.prefix(8)) photos=\(d.photos.count) found=\(have.count) folder=\(f.path)")
        return have
    }
    static func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// **앱이 스스로 적는 계측**(`CLAUDE.md` 빌드 ⓒ — *"적게 만드는 것이 절반이다"*). `capture-drafts/draft.log`에 한 줄씩.
    /// 폰에서 난 일을 맥에서 읽는 유일한 길이다(`devicectl device copy from … capture-drafts`). 상태를 안 바꾼다.
    /// ⚠️ 초안을 지워도 이 파일은 남는다(초안 폴더가 아니라 그 옆이다). 커지면 그때 자른다.
    static func log(_ line: String) {
        guard let dir = dir() else { return }
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss.SSS"
        let entry = "\(f.string(from: Date())) \(line)\n"
        let url = dir.appendingPathComponent("draft.log")
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd(); try? h.write(contentsOf: Data(entry.utf8))
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }
}
