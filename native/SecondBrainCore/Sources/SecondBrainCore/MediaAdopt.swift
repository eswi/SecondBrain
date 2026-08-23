import Foundation

/// **iCloud에서 받은 것을 로컬로 들여오는 규칙** — 설계 `docs/native/media-icloud-design.md` §2-A(C안)·§5.
///
/// ## 왜 있나 — 보안 스코프의 수명 문제를 **없애는** 쪽으로 풀었다
///
/// `FragmentFolder.withFolder`는 스코프를 열고 **함수가 돌아올 때 닫는다.** 그래서 iCloud 쪽 URL을
/// 돌려주면 **읽는 순간에는 스코프가 닫혀 있다.** 후보가 셋이었다(설계 §2-A):
///
/// - A: 스코프 안에서 `Data`로 다 읽어 돌려준다 → **자료 확장(동영상)에서 깨진다**
/// - B: 「빌린다/반납한다」 짝으로 화면이 열려 있는 동안 열어 둔다 → **`defer`를 잃는다**(짝을 놓치면 조용히 누수)
/// - **C(채택):** **바이트가 온 순간 로컬로 복사하고, 그 뒤로는 기존 「로컬 우선 찾기」가 찾는다**
///
/// **C를 고른 결정적 이유(사용자 2026-08-20): 「추정 위에 설계를 안 얹는다」.**
/// 「macOS는 샌드박스가 없어 스코프가 no-op이다」·「iOS는 로컬 사본이 가리고 있을 뿐이다」는 **둘 다 추정이다.**
/// A·B는 그 답에 따라 설계가 달라지는데 **C는 무관하다 — 스코프 밖에서 읽는 코드가 아예 없어진다.**
///
/// **그리고 정직하다:** 「받는 중」이 **파일당 한 번**으로 끝난다. A·B는 evict될 때마다 다시 받아
/// 사용자가 「아까 받았는데 또?」가 된다.
public enum MediaAdoptJudge {
    /// **들여올 것인가.** 로컬에 없고 iCloud 쪽에 **바이트가 실제로 있을 때만.**
    ///
    /// - `localExists`: 로컬에 이미 있나. 있으면 **iCloud를 볼 일이 없다**(§4의 로컬 우선 — 폰의 정상 경로).
    /// - `cloudBytesPresent`: iCloud 쪽 **실체가 내려와 있나.**
    ///   ⚠️ **이름만 있는 것(dataless)으로는 안 된다**(§0-B) — 복사해도 **빈 파일**이 되고,
    ///   그러면 **로컬이 「바이트가 보장된 층」이라는 전제가 깨진다**(§4). 그게 깨지면 찾는 순서 자체가 무의미해진다.
    public static func shouldAdopt(localExists: Bool, cloudBytesPresent: Bool) -> Bool {
        !localExists && cloudBytesPresent
    }
}

/// 들여오는 동안 쓰는 **임시 이름** — 원자성(§3과 같은 패턴: 임시로 복사 → 같은 폴더에서 rename).
public enum MediaAdoptNaming {
    /// 임시 파일 접두사.
    public static let prefix = "sb-adopting-"
    /// 임시 파일 **확장자** — 자료 확장자(`m4a`/`jpg`)와 **반드시 달라야 한다.** 아래 이유를 볼 것.
    public static let partExtension = "part"

    /// `sb-adopting-<id>.m4a.part`
    ///
    /// > ### ⛔ 왜 뒤에 `.part`를 붙이나 — 안 붙이면 **업로더가 임시 파일을 올린다**
    /// > `AudioStore.localFiles()`/`PhotoStore.localFiles()`는 로컬 디렉터리를 **확장자로 걸러**
    /// > 업로더의 **차집합 왼쪽**을 만든다(§3·§5). 임시 이름이 `sb-adopting-<id>.m4a`라면
    /// > **그 필터를 통과해** 업로더가 그것을 「확정된 로컬 파일」로 보고,
    /// > id를 `sb-adopting-<id>`로 계산해 **iCloud에 엉뚱한 이름의 파일을 올린다.**
    /// > 그 파일은 어느 항목의 포인터와도 안 맞아 **고아**가 되고, 차집합이 매번 다시 계산되므로
    /// > **지워도 다음 실행이 또 올린다**(§5의 「지우면 끝이 아니다」와 같은 함정).
    /// >
    /// > **확장자를 `part`로 두면 그 필터에 애초에 안 걸린다.** 접두사만으로 막지 않는 이유는
    /// > **필터가 확장자를 보기 때문**이다 — 막는 쪽과 걸러지는 쪽을 **같은 값**으로 맞춘다.
    ///
    /// ⚠️ **축이 파일명으로 바뀌었다**(2026-08-23 · C). 옛 꼴은 id를 받아 확장자를 붙였다 —
    /// **옛 이름에서는 결과가 글자 그대로 같다**(`MediaAdoptTests`가 못 박는다).
    /// `kind`는 이제 이름 계산에 안 쓰이지만 **호출 자리를 종류별로 읽히게** 남긴다.
    public static func partName(kind: MediaKind, name: String) -> String {
        "\(prefix)\(name).\(partExtension)"
    }

    /// 들여오다 만 찌꺼기인가 — 청소가 이 이름으로 찾는다.
    public static func isPartName(_ name: String) -> Bool {
        name.hasPrefix(prefix) && name.hasSuffix(".\(partExtension)")
    }

    /// **임시 이름이 「확정 파일」 필터에 걸리나** — 걸리면 위 ⛔가 실제로 일어난다.
    /// 시험이 이것을 못박는다(`localFiles()`가 확장자로 거르는 것과 **같은 계산**).
    public static func looksLikeFinalizedFile(_ name: String, kind: MediaKind) -> Bool {
        (name as NSString).pathExtension == kind.ext
    }
}
