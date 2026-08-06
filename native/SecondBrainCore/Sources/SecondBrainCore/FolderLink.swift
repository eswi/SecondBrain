import Foundation

/// **폴더 연결 상태** — 사양서 §0-A-1. 원칙: **연결이 끊긴 것과 비어 있는 것을 절대 같게 보이지 않는다.**
///
/// 이 판정이 없던 동안 **조용히 비는 길이 다섯인데 화면에선 전부 "새 기억이 없어요"** 였다.
/// 폴더 연결이 끊기면 **사용자 눈에는 기억 전체가 사라진 것**이고, 파일은 iCloud에 그대로 있는데
/// 사람은 그것을 알 방법이 없어 **그 순간 앱을 지웠다 깔 수도 있다.**
///
/// **판정을 여기(Core)에 두는 이유:** 실제 접근은 `UserDefaults`·보안 스코프·파일 시스템에 묶여 있어
/// App 타깃에서는 헤드리스로 못 잡는다. **사실 수집(I/O)은 App이 하고 판정만 여기서** 한다 —
/// 분류 게이트를 `ItemSchedule`로, 회차 판정을 `Recurrence`로 올린 것과 같은 구조다.
public enum FolderLink: Equatable, Sendable {
    /// 아직 폴더를 안 골랐다(북마크 없음). 앱 첫 실행, 또는 앱을 지웠다 깐 뒤.
    case notChosen
    /// 골랐는데 **못 연다** — 북마크 해소 실패 / 접근 거부 / 목록 읽기 실패.
    /// **이유는 갈라 보여주지 않는다**(사람이 할 일이 같다: 다시 연결). 오류 코드와 원인의 대응이
    /// 문서로 보장되지 않아 **추측을 문장으로 만들면 틀린 안내**가 되기 때문이기도 하다.
    case unreachable
    /// 폴더는 열렸고 조각 파일도 있는데 **하나도 못 읽었다** — iCloud에서 아직 안 내려온 상태.
    /// **새 기기에서 가장 흔한 경로**이고, 이 판정이 없으면 "비었다"와 구분되지 않는다.
    case downloading
    /// 폴더는 열렸는데 조각 파일이 **0개**. **사고가 아니라 정상 상태다**(새 폴더를 막 골랐을 때).
    /// ⚠️ **여기에는 "파일은 안전합니다"를 말하지 않는다** — 폴더는 열렸는데 파일이 사라진 경우도
    /// 이 상태로 오므로 그 말이 **거짓일 수 있다.**
    case empty
    /// 정상. `files` = **실제로 읽힌** 조각 파일 수.
    case ok(files: Int)

    /// 목록 대신 안내 화면을 보여줘야 하는 상태인가.
    public var needsGuidance: Bool {
        switch self {
        case .notChosen, .unreachable, .downloading, .empty: return true
        case .ok: return false
        }
    }
    /// 폴더를 아직 못 쓰는 상태인가(설정의 버튼이 "선택"인지 "변경"인지 가른다).
    public var isLinked: Bool {
        switch self {
        case .notChosen: return false
        default: return true
        }
    }
    /// **지금 새 기억을 담을 수 있나** — 수집(마이크) 노출 조건.
    ///
    /// ⚠️ **`empty`는 담을 수 있어야 한다.** 그 화면의 안내가 *"아래 마이크를 눌러 말하거나 적어보세요"* 인데
    /// 마이크가 없으면 **화면이 거짓말을 한다.** (옛 코드는 "안내 화면인가" 하나로 마이크를 숨겨서,
    /// 이 상태를 만들자마자 그 모순이 생길 뻔했다.)
    /// 나머지 셋은 **쓸 곳이 없거나(못 연다·안 골랐다) 쓰면 위험하다(받는 중 — 아직 안 온 것 위에 쌓게 된다).**
    public var canCapture: Bool {
        switch self {
        case .empty, .ok: return true
        case .notChosen, .unreachable, .downloading: return false
        }
    }
}

public enum FolderLinkJudge {
    /// **사실 여섯 개로 상태를 정한다.** 전부 App이 실제로 시도해 본 결과여야 한다 —
    /// **저장값(북마크가 있나)만으로는 원리적으로 못 가른다. 읽어봐야 안다.**
    /// (옛 판정이 정확히 그 잘못이었다: `hasFolder`가 `UserDefaults`에 데이터가 있는지만 봤다.)
    ///
    /// - `bookmarkExists`: 저장된 북마크가 있나
    /// - `resolved`: 그 북마크가 URL로 풀렸나
    /// - `accessGranted`: 보안 스코프 접근이 열렸나 — **옛 코드는 이 반환값을 보지도 않았다**
    /// - `directoryListed`: 디렉터리 목록을 읽었나
    /// - `fragmentFiles`: 목록에 잡힌 `inbox*.md` 수
    /// - `readableFiles`: 그중 **내용까지 읽힌** 수
    ///
    /// **일부만 읽힌 경우(`0 < readable < fragment`)는 `ok`로 본다** — 앱을 쓸 수 있고, 못 읽은 것은
    /// 다음 로드에서 채워진다. 대신 `files`가 평소보다 **작은 수로 보이는 것 자체가 신호**가 된다
    /// (설정 화면이 이 수를 보여준다).
    public static func status(bookmarkExists: Bool, resolved: Bool, accessGranted: Bool,
                              directoryListed: Bool, fragmentFiles: Int, readableFiles: Int) -> FolderLink {
        guard bookmarkExists else { return .notChosen }
        // 셋 중 하나라도 막히면 "못 연다" — 어디서 막혔는지는 사람이 할 일을 안 바꾼다.
        guard resolved, accessGranted, directoryListed else { return .unreachable }
        guard fragmentFiles > 0 else { return .empty }
        guard readableFiles > 0 else { return .downloading }
        return .ok(files: readableFiles)
    }
}
