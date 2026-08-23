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
    /// **수집 때 이름을 만드는 자리** — `finalize`만 쓴다. `<항목id>.m4a`.
    ///
    /// ⛔ **조회는 이것을 안 쓴다**(2026-08-23 · C). 조회는 **포인터 값을 받는다**(`url(name:)` 등) —
    /// id에서 이름을 계산하는 것이 **「한 항목에 자료 하나」의 원인**이었다(제약 9-a).
    /// ⏸ **추가 기능(3단계)이 `<항목id>-<자료id>.m4a`를 만든다** — 그때 이 함수 밖에서 만든다(§3-W-6).
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
        // ⚠️ **확장자가 여기서 두 번째 일을 한다** — 들여오기 임시 파일(`sb-adopting-<id>.m4a.part`)을
        // 걸러내는 것도 이 필터다(`MediaAdoptNaming`의 ⛔ 참고: 걸리면 업로더가 임시 파일을 올려 고아를 만든다).
        // 접두사 검사를 **함께** 두는 이유: 나중에 이 필터를 손대는 사람이 그 연결을 모를 수 있다.
        return e.filter { $0.pathExtension == "m4a" && !MediaAdoptNaming.isPartName($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
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

    /// 이 기기에서 재생 가능한 음성 파일 URL. **로컬만 본다.**
    ///
    /// ## ⛔ iCloud URL을 돌려주지 않는다 (§2-A C안 · 2026-08-20)
    ///
    /// 여기엔 `MediaCloud.readableURL(.audio, id:)` 폴백이 있었다. **iCloud 쪽 URL을 돌려주는데
    /// 돌려받은 쪽이 읽을 때는 보안 스코프가 닫혀 있었다.** C안으로 닫았다 —
    /// **바이트가 있으면 `adoptFromCloudIfNeeded`가 로컬로 옮기고, 그 뒤엔 아래 로컬 조회가 그냥 찾는다.**
    ///
    /// **그래서 이 함수는 순수한 로컬 조회다.** 화면이 쓰기 전에 `MediaFetch`가 들여오기를 끝내 둔다
    /// (`MediaFetch.availability`가 **메인 밖에서** 먼저 부른다 — 화면 그리는 중에 파일 복사를 하지 않는다).
    ///
    /// ⚠️ **nil의 뜻이 좁아졌다:** 「이 기기 로컬에 없다」다. iCloud에 있는지는 **이 함수가 답하지 않는다** —
    /// 그것은 `availability(name:)`의 일이다(§4의 세 갈래).
    ///
    /// ## ★ 축이 「항목 id」에서 **「파일명」**으로 바뀌었다 (2026-08-23 · C · 설계 §3-X)
    /// 조회는 이제 **포인터 필드의 값**(= 파일명)을 받는다. **id에서 이름을 계산하지 않는다** —
    /// 그것이 「한 항목에 자료 하나」를 만들던 자리였다(제약 9-a·9-b).
    /// ⚠️ **옛 파일은 이름을 안 바꾼다** — 포인터 값이 `<항목id>.<확장자>`이므로 그대로 찾힌다(§6).
    static func url(name: String) -> URL? {
        let fm = FileManager.default
        for dir in searchDirs() {
            let u = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: u.path) { return u }   // 로컬은 dataless가 없다 = 있으면 곧 바이트가 있다
        }
        return nil
    }

    /// **iCloud에 바이트가 있고 로컬에 없으면 로컬로 들여온다**(§2-A C안). 들여왔으면 true.
    ///
    /// **로컬에 이미 있으면 iCloud I/O를 아예 안 한다** — 폰의 정상 경로에서 비용이 0이다(§5).
    /// 실제로 도는 것은 **Mac**과 나중의 두 번째 기기다.
    @discardableResult
    static func adoptFromCloudIfNeeded(name: String) -> Bool {
        let fm = FileManager.default
        let localExists = searchDirs().contains { fm.fileExists(atPath: $0.appendingPathComponent(name).path) }
        guard !localExists, let dir = localAudioDir() else { return false }
        MediaCloud.sweepAdoptLeftovers(in: dir)
        return MediaCloud.adopt(.audio, name: name, intoDir: dir)
    }

    /// **세 갈래 판정** (§4) — 「여기 있다」 · 「아직 안 받았다」 · 「어디에도 없다」.
    /// `url(name:)`는 「볼 수 있나」만 답하므로 **뒤의 둘을 못 가른다.** 화면이 그 둘을 갈라 말해야 한다.
    static func availability(name: String) -> MediaAvailability {
        let fm = FileManager.default
        // 로컬이 먼저 — 여기서 잡히면 iCloud I/O를 **아예 하지 않는다**(폰의 정상 경로).
        if searchDirs().contains(where: { fm.fileExists(atPath: $0.appendingPathComponent(name).path) }) {
            return .here
        }
        let c = MediaCloud.cloudFacts(.audio, name: name)
        return MediaAvailabilityJudge.status(localExists: false,
                                            cloudNameExists: c.nameExists,
                                            cloudBytesPresent: c.bytesPresent)
    }
}
