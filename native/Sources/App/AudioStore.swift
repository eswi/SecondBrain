import Foundation

/// 원본 음성 파일 저장소 — 항목 UUID로 이름 붙인 `.m4a`를 관리한다.
/// 원칙: **원본 미디어는 불변(write-once) · 텍스트 층만 가변.** 음성은 STT의 진실 기준(ground truth) —
/// 나중에 직접 듣고 텍스트를 고치거나 더 나은 STT에 다시 맡길 수 있게 원본을 보존한다.
///
/// **기본은 기기에만**(앱 샌드박스) — 온디바이스 STT의 "음성이 기기 밖으로 안 나감"(사양서 §7) 유지.
/// 저장 위치는 `searchDirs()`로 추상화되어, 나중에 iCloud 위치를 탐색 목록에 더하기만 하면
/// **항목별 iCloud 동기화**를 재생에 자동 반영한다(설계 `docs/native/audio-capture-design.md` §7).
/// 포인터 필드 `audio:`는 **정체성(파일명)** 만 담고, 동기화 여부는 미래에 **별도 필드**로 분리한다.
enum AudioStore {
    /// 포인터 필드 값 = 파일명. 항목 id와 1:1(결정적).
    static func filename(forId id: String) -> String { "\(id).m4a" }

    // MARK: 디렉터리

    /// 로컬(기기 전용) 음성 디렉터리. 없으면 만든다. 실패 시 nil.
    private static func localAudioDir() -> URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("SecondBrain/audio", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// id로 음성을 찾을 때 탐색할 위치들(순서대로). 지금은 로컬만.
    /// **향후 확장(§7):** iCloud 폴더의 `audio/`를 여기 더하면 항목별 동기화가 재생에 자동 반영된다.
    private static func searchDirs() -> [URL] {
        [localAudioDir()].compactMap { $0 }
    }

    // MARK: 임시(캡처 중) — 시트 세션 동안 이어 쓰다가 [저장] 때 확정

    /// 새 캡처 세션용 임시 파일 URL(파일 생성은 녹음기가 한다).
    static func newTempURL(sessionId: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sb-capture-\(sessionId).m4a")
    }

    /// 임시 파일 삭제([취소]/미저장 종료 시).
    static func deleteTemp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: 확정(불변) · 조회

    /// 임시 파일을 `<id>.m4a`로 확정(이동). 이후 재오픈 없음 = **write-once·불변**.
    /// 성공 시 저장할 포인터 파일명 반환, 실패/파일없음이면 nil(→ 항목은 음성 없이 생성).
    @discardableResult
    static func finalize(temp: URL, forId id: String) -> String? {
        guard let dir = localAudioDir() else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: temp.path) else { return nil }
        let dest = dir.appendingPathComponent(filename(forId: id))
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }  // UUID 충돌은 사실상 없음(방어)
            try fm.moveItem(at: temp, to: dest)
            return filename(forId: id)
        } catch {
            return nil
        }
    }

    /// 이 기기에서 재생 가능한 음성 파일 URL. nil이면 다른 기기에서 녹음됨(미동기화).
    static func url(forId id: String) -> URL? {
        let name = filename(forId: id)
        let fm = FileManager.default
        for dir in searchDirs() {
            let u = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: u.path) { return u }
        }
        return nil
    }
}
