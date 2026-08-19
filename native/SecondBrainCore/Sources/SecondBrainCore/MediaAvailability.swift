import Foundation

/// **자료가 지금 볼 수 있는 상태인가** — 설계 `docs/native/media-icloud-design.md` §4.
///
/// 옛 판정은 `url(forId:)`가 **URL 아니면 nil** 하나였다. **두 값으로는 세 상태를 못 담는다** —
/// iCloud 파일은 **이름은 있는데 바이트가 없는 상태**가 있고(§0-B에서 쟀다:
/// `fileExists` = true인데 `totalFileAllocatedSize` = 0), 그것을 「없다」와 뭉치면
/// **파일은 iCloud에 그대로 있는데 사람은 그것을 알 방법이 없다.**
///
/// **새 원칙이 아니라 있는 원칙의 적용이다** — `FolderLink`가 세운 것과 같다:
/// *"연결이 끊긴 것과 비어 있는 것을 절대 같게 보이지 않는다."*
public enum MediaAvailability: String, Sendable, Equatable {
    /// **바이트가 있다.** 로컬이든, 내려온 iCloud든. → 재생 버튼 · 사진.
    case here
    /// **iCloud엔 있는데 실체가 없다.** → 받기 시작 + 「원본 … 받는 중…」. **이 상태가 새로 생겼다.**
    case notDownloaded
    /// **이 기기에도 iCloud에도 없다.** → 지금 문구 그대로(「원본 음성 있음 · 이 기기엔 없음」).
    case absent
}

public enum MediaAvailabilityJudge {
    /// **찾는 순서 = [로컬, iCloud]** (§4). 로컬이 먼저인 이유는 **로컬이 바이트가 반드시 있는 층**이라서다.
    ///
    /// - `localExists`: 로컬(앱 샌드박스)에 파일이 있나. **로컬은 dataless가 없으므로 있으면 곧 바이트가 있다.**
    /// - `cloudNameExists`: iCloud 쪽에 **이름이라도** 있나.
    ///   ⚠️ **`fileExists` 하나로 재는 값이다 — dataless에도 true다**(§0-B). 그래서 이것만으로 `.here`를 못 준다.
    /// - `cloudBytesPresent`: iCloud 쪽 실체가 **내려와 있나**(다운로드 상태/할당 크기로 재야 한다).
    ///
    /// **중복은 정상이고 해소가 필요 없다** — 원본은 write-once·불변이라 같은 id의 두 사본은
    /// 내용이 같은 것이 보장된다(`edit-policy.md` §6). 첫 히트를 쓴다.
    public static func status(localExists: Bool,
                              cloudNameExists: Bool,
                              cloudBytesPresent: Bool) -> MediaAvailability {
        // 바이트가 있는 쪽이 하나라도 있으면 볼 수 있다. (`cloudBytesPresent`가 참이면 이름은 당연히 있다 —
        // 어긋난 입력이 와도 **바이트 쪽을 믿는다**: 볼 수 있는 것을 못 본다고 말하지 않는다.)
        if localExists || cloudBytesPresent { return .here }
        // ⚠️ 여기가 핵심 갈림. 이 줄이 없으면 「아직 안 받았다」가 「없다」로 뭉쳐진다.
        if cloudNameExists { return .notDownloaded }
        return .absent
    }
}
