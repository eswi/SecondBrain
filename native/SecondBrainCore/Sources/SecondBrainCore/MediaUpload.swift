import Foundation

/// **자료 올리기 — 판정과 문구.** 설계 `docs/native/media-icloud-design.md` §3·§5·§8.
/// 실제 복사·rename은 App(`MediaUploader`)이 한다.

public enum MediaUploadJudge {
    /// **첫 실행 한도** (§5 · 2026-08-19 사용자 결정). 5개면 `audio/`·`photo/` 양쪽에 파일이 생기는지
    /// 보기 충분하고, **잘못됐을 때 치울 것이 5개뿐**이다.
    public static let firstRunLimit = 5

    /// 이번 실행에 올릴 **최대 개수**. nil이면 무제한.
    ///
    /// **한도가 걸리는 조건이 「iCloud 쪽 자료가 0개」인 이유:** 상태를 아무데도 안 적고
    /// **「첫 실행인가」를 iCloud 폴더를 보고 안다.** 대상을 차집합으로 계산하는 것과 같은 방식이고
    /// **멱등이 안 깨진다**(§5).
    public static func limit(cloudMediaCount: Int) -> Int? {
        cloudMediaCount == 0 ? firstRunLimit : nil
    }

    /// 한도를 적용한 뒤 **「나머지가 남았나」**. 남았으면 화면이 그렇게 말해야 한다(§8 완료 문구).
    public static func capped(total: Int, limit: Int?) -> Bool {
        guard let limit else { return false }
        return total > limit
    }
}

/// 업로드 로그 — **실패만 적는다**(2026-08-19 사용자 결정).
///
/// **왜 성공을 안 적나:** 131줄이 쌓이면 `.sb-media.log`의 「두 줄이면 정상」이 무너진다.
/// 그리고 **성공은 iCloud 폴더의 파일 자체가 증거**라 줄이 중복이다.
/// → §2-A의 원칙 그대로: **로그는 예상과 다른 것만 적는다. 정상이면 0줄.**
public enum MediaUploadLog {
    /// 실패 한 줄. 자리 로그와 **같은 파일**(`MediaPlaceLog.fileName`)에 쓴다 — 볼 곳이 하나여야 한다.
    ///
    /// 셋째 칸이 `upload`라서 자리 로그 판정(`MediaPlaceLog.last`)에 **안 걸린다** —
    /// 그쪽은 셋째 칸이 `audio`/`photo`인 줄만 읽는다.
    /// 원인은 **`<domain>/<code>`, 시스템이 준 값 그대로.**
    public static func failureLine(at timestamp: String, device: String,
                                  kind: MediaKind, id: String, err: String?) -> String {
        var s = "\(timestamp) \(device) upload \(kind.rawValue) \(id)"
        if let err { s += " err=\(err)" }
        return s + "\n"
    }
}

/// **화면 문구** (§8) — 2026-08-19에 **사용자가 고른 말**이다.
///
/// ⚠️ **임의 변경 금지**(CLAUDE.md 항시 규칙 6). 여기 두고 시험으로 못박는 이유가 그것이다 —
/// 코드 어딘가에 문자열로 흩어져 있으면 다음 세션이 「다듬는다」며 바꾼다.
public enum MediaMigrationText {
    /// 진행 중 — 「자료 옮기는 중 · 12/131」
    public static func progress(moved: Int, total: Int) -> String {
        "자료 옮기는 중 · \(moved)/\(total)"
    }
    /// 첫 실행 한도에서 멈췄을 때 — 「자료 5개를 옮겼어요 · 나머지는 다음에」
    ///
    /// **왜 이 말인가**(사용자 근거 2026-08-19): 「5/131」은 진행 배너와 **같은 꼴이라 멈춘 것인지
    /// 도는 것인지 안 갈린다.** 아무 말 없이 사라지면 첫 실행에 무슨 일이 있었는지 모른다.
    /// 이 문구는 **끝났다는 것과 아직 남았다는 것을 둘 다** 말한다.
    public static func cappedDone(moved: Int) -> String {
        "자료 \(moved)개를 옮겼어요 · 나머지는 다음에"
    }
    /// 받는 중 (§6) — 종류마다 다르다.
    public static func downloading(_ kind: MediaKind) -> String {
        switch kind {
        case .audio: return "원본 음성 받는 중…"
        case .photo: return "원본 사진 받는 중…"
        }
    }
    /// 받기 실패 — **원인을 짚지 않는다.** 오류와 원인의 대응이 문서로 보장되지 않아
    /// 추측을 문장으로 만들면 틀린 안내가 된다(`FolderLink.unreachable`과 같은 경계).
    public static let downloadFailed = "아직 못 받았어요 · 다시 시도"

    /// **사진 촬영 위치 핀의 이름** — 사용자가 고름(2026-08-20).
    ///
    /// **두 자리가 이 값을 함께 쓴다:** 앱 안 지도의 `Marker`, 그리고 **지도 앱을 열 때의 핀 이름.**
    /// 사용자가 *"앱 안과 지도 앱이 같아야 한다"*는 이유로 고른 값이라 **한 곳에 둔다** —
    /// 두 군데 문자열로 두면 한쪽만 고쳐져 **말이 갈린다.**
    public static let photoPinName = "촬영 위치"
}
