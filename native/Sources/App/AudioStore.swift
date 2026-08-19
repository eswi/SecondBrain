import Foundation
import SecondBrainCore

/// 원본 음성 파일 저장소 — 항목 UUID로 이름 붙인 `.m4a`를 관리한다.
/// 원칙: **원본 미디어는 불변(write-once) · 텍스트 층만 가변.** 음성은 STT의 진실 기준(ground truth) —
/// 나중에 직접 듣고 텍스트를 고치거나 더 나은 STT에 다시 맡길 수 있게 원본을 보존한다.
///
/// **확정은 지금도 로컬에만 한다**(앱 샌드박스) — 온디바이스 STT의 "음성이 기기 밖으로 안 나감"(사양서 §7) 유지.
///
/// ⚠️ **옛 서술이 뒤집혔다 (2026-08-19).** 여기엔 *"나중에 iCloud 위치를 탐색 목록(`searchDirs()`)에
/// 더하기만 하면"* 이라고 적혀 있었다. **그 방식은 안 된다** — iCloud 쪽은 보안 스코프를 열어야 보이고
/// **자리(하위 폴더/루트)를 먼저 계산**해야 해서 URL 목록에 안 담긴다. 그래서 iCloud는 `MediaCloud`가
/// 따로 보고, 찾는 순서는 **[로컬, iCloud]** 두 층으로 갈렸다(설계 `media-icloud-design.md` §4).
/// **유지되는 것:** 확정 목적지는 여전히 로컬이고(§3), **포인터 필드 `audio:`는 파일명만 담는 성역**이다 —
/// 자리가 어디로 정해지든 **값이 안 바뀐다.**
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

    /// id로 음성을 찾을 때 탐색할 **로컬** 위치들.
    ///
    /// ⚠️ **iCloud는 여기 들어오지 않는다.** 옛 주석은 *"iCloud 폴더의 `audio/`를 여기 더하면"* 이라고
    /// 예고했지만, iCloud 쪽은 **보안 스코프를 열어야** 보이고 **자리(하위 폴더/루트)를 먼저 계산**해야 해서
    /// URL 목록으로는 안 담긴다. 그래서 iCloud는 `MediaCloud`가 따로 본다(설계 §4 · 2026-08-19).
    /// **찾는 순서 = [로컬, iCloud]** — 로컬이 먼저인 이유는 **로컬이 바이트가 반드시 있는 층**이라서다.
    private static func searchDirs() -> [URL] {
        [localAudioDir()].compactMap { $0 }
    }

    /// 로컬에 있는 확정 음성 파일 전부 — **업로더의 차집합 왼쪽**(§3·§5).
    /// 임시 파일은 여기 안 들어온다(그쪽은 `temporaryDirectory`에 있다).
    static func localFiles() -> [URL] {
        guard let dir = localAudioDir() else { return [] }
        let e = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return e.filter { $0.pathExtension == "m4a" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
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
            if fm.fileExists(atPath: u.path) { return u }   // 로컬은 dataless가 없다 = 있으면 곧 바이트가 있다
        }
        // 로컬에 없으면 iCloud — **바이트가 있는 것만** 돌려준다(§0-B의 「이름만 있는 파일」을 걸러낸다).
        return MediaCloud.readableURL(.audio, id: id)
    }

    /// **세 갈래 판정** (§4) — 「여기 있다」 · 「아직 안 받았다」 · 「어디에도 없다」.
    /// `url(forId:)`는 「볼 수 있나」만 답하므로 **뒤의 둘을 못 가른다.** 화면이 그 둘을 갈라 말해야 한다.
    static func availability(forId id: String) -> MediaAvailability {
        let fm = FileManager.default
        let name = filename(forId: id)
        // 로컬이 먼저 — 여기서 잡히면 iCloud I/O를 **아예 하지 않는다**(폰의 정상 경로).
        if searchDirs().contains(where: { fm.fileExists(atPath: $0.appendingPathComponent(name).path) }) {
            return .here
        }
        let c = MediaCloud.cloudFacts(.audio, id: id)
        return MediaAvailabilityJudge.status(localExists: false,
                                            cloudNameExists: c.nameExists,
                                            cloudBytesPresent: c.bytesPresent)
    }
}
