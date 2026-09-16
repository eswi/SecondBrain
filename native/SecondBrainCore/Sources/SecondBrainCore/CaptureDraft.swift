import Foundation

/// **수집 초안 — 「쓰다 만 기억」** (2026-09-15 사용자 결정 · 정본 = `docs/native/capture-draft-design.md`).
///
/// 수집 화면에서 적고 있던 것이 **의도와 다르게** 끊겼을 때(앱이 죽음·재시작) 되살릴 재료다.
/// **기억이 아니다** — `inbox*.md`에 안 들어가고 UUID 항목도 아니다. **기기 로컬 파일**이고 iCloud로 안 넘어간다.
///
/// **언제 지워지나 = 의도한 종료 둘**([저장] · [취소하기]). 그 밖의 모든 끝에는 남는다.
/// 그래서 「의도와 다르게 끊겼나」를 따로 판정하지 않는다 — **파일이 남아 있다는 것 자체가 그 뜻**이다.
///
/// 파일 배치(`CaptureDraftStore`): `<dir>/<id>.json` + 사진 폴더 `<dir>/<id>/`.
/// ⚠️ **녹음 원본은 초안에 없다** — 앱이 죽으면 m4a가 마무리되지 않아 못 쓸 수 있고, 글(실시간 전사)은 이미 `text`에 있다.
public struct CaptureDraft: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var text: String
    /// 초안 폴더(`CaptureDraftStore.folder`) **안의 파일 이름**들. 순서 = 카드 순서(첫째가 얼굴).
    public var photos: [String]
    /// 정규화된 URL 문자열들 — 파일이 없다(값이 자료 자신).
    public var urls: [String]
    /// 밀리초(UTC epoch).
    public let createdAt: Int64
    public var updatedAt: Int64

    public init(id: String = UUID().uuidString, text: String = "", photos: [String] = [], urls: [String] = [],
                createdAt: Int64, updatedAt: Int64) {
        self.id = id; self.text = text; self.photos = photos; self.urls = urls
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// **남길 것이 없나** — 글이 비었고(공백만) 사진·URL도 없다. 이런 초안은 저장하지 않고, 있던 것이면 지운다.
    public var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photos.isEmpty && urls.isEmpty
    }
}

/// 초안 파일 저장소 — **디렉터리를 밖에서 받는다**(시험이 임시 폴더를 준다 · `InboxStore`와 같은 결).
public enum CaptureDraftStore {
    /// `<dir>/<id>.json`
    public static func file(id: String, in dir: URL) -> URL { dir.appendingPathComponent("\(id).json") }
    /// 초안의 사진이 사는 폴더 `<dir>/<id>/`. **없으면 만든다.**
    public static func folder(id: String, in dir: URL) -> URL {
        let f = folderURL(id: id, in: dir)
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        return f
    }
    /// 같은 자리 — **만들지 않는다.** 「이 파일이 초안 폴더 안에 있나」를 견줄 때 쓴다(2026-09-17).
    /// ⚠️ `folder(id:in:)`로 견주면 **지운 초안의 빈 폴더가 다시 생긴다**(`closeDraft` 뒤 `discardTemps`가 부르는 순서).
    public static func folderURL(id: String, in dir: URL) -> URL {
        dir.appendingPathComponent(id, isDirectory: true)
    }

    /// 전부 — **최근에 고친 것이 앞**(`updatedAt` 내림차순). 깨진 파일·다른 파일은 건너뛴다.
    public static func list(in dir: URL) -> [CaptureDraft] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let dec = JSONDecoder()
        var out: [CaptureDraft] = []
        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url), let d = try? dec.decode(CaptureDraft.self, from: data) else { continue }
            out.append(d)
        }
        return out.sorted { a, b in a.updatedAt != b.updatedAt ? a.updatedAt > b.updatedAt : a.id < b.id }
    }

    /// 한 초안을 적는다(덮어쓴다). ⚠️ **빈 초안은 적지 않고 지운다** — 「남길 것이 없는 초안」이 목록에 뜨지 않게.
    public static func write(_ d: CaptureDraft, in dir: URL) throws {
        if d.isBlank { delete(id: d.id, in: dir); return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        try enc.encode(d).write(to: file(id: d.id, in: dir), options: .atomic)
    }

    /// 초안 하나를 **파일·사진 폴더까지** 지운다. 없어도 조용히 지나간다.
    public static func delete(id: String, in dir: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: file(id: id, in: dir))
        try? fm.removeItem(at: dir.appendingPathComponent(id, isDirectory: true))
    }
}
