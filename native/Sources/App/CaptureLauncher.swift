import SwiftUI

/// **수집 화면에 어떻게 들어왔나** — **나가는 뜻이 갈린다**(2026-08-31 사용자 결정).
///
/// 사용자: *"살아있는 기억 화면에서 + 기호 눌러서 수집 화면으로 들어온 경우는 `<` 아이콘이 존재해야
/// 하고 의미가 있지만 (되돌아간다는) 취소하기는 좀 더 확장된 의미야. 앱 밖에서 핫키 눌러서 들어온
/// 경우는 그냥 앱을 종료시켜야 해. … 이 경우 `<` 아이콘은 없어야 하고 취소하기 누르면 그냥 앱 밖으로
/// 나가야 해."*
///
/// ★ **그래서 `<`는 「되돌아간다」이고 [취소하기]는 「이 수집을 그만둔다」다** — 앱 안에서는 둘이 같은
/// 곳으로 가지만 **뜻이 다르다.**
///
/// ## ⛔ **`<`는 어떻게 들어왔든 늘 있다** (2026-08-31 사용자가 다시 정했다)
/// > *"어떤 식으로 진입을 하더라도 수집 화면에서는 `<` 기호를 두기로 하고, 앱 밖에서 바로 수집
/// > 화면으로 들어온 경우 `<` 기호를 누르면 '새로운 기억' 화면으로 가기로 하자."*
///
/// **옛 서술(지우지 않는다 · 반나절 만에 뒤집혔다):** *"핫키로 들어오면 돌아갈 화면이 없으므로
/// `<`가 아예 없다."* — **돌아갈 화면이 없는 것이 아니라 「새로운 기억」이 그 자리였다.**
///
/// | 들어온 길 | `<` | [취소하기] |
/// |---|---|---|
/// | **`.inApp`** | 있다 → **온 화면으로** | 수집을 그만두고 **온 화면으로** |
/// | **`.hotkey`** | 있다 → **「새로운 기억」으로** | **앱 밖으로** |
///
/// ★ **그래서 갈리는 것은 [취소하기] 하나다** — `<`는 둘 다 「앱 안에 머문다」다.
enum CaptureOrigin {
    /// 앱 안에서 `+`를 눌러 들어왔다 — 나가면 **그 화면으로 되돌아간다.**
    case inApp
    /// 앱 밖에서 액션 버튼·단축어(핫키)로 들어왔다 — 나가면 **앱 밖으로 나간다.**
    case hotkey
}

/// 앱 밖(액션 버튼·단축어)에서 "수집 시트를 열어라"를 앱에 전달하는 공유 신호.
/// App Intent가 `requestCapture()`를 부르면 RootView가 관찰해 CaptureSheet를 띄운다.
@MainActor
final class CaptureLauncher: ObservableObject {
    static let shared = CaptureLauncher()
    private init() {}

    @Published var showCapture = false

    /// **이 프로세스가 언제 떴나** — `.shared`가 처음 만들어지는 순간이고, 그것은 **앱이 뜨는 순간**이다
    /// (`RootView`가 launch 때 `.shared`를 잡는다). **핫키가 앱을 새로 깨웠는지** 가르는 데 쓴다.
    private static let processStarted = Date()

    /// 핫키로 열 때 **그 순간의 탭** — [취소하기]로 나갈 때 **그 화면으로 되돌린다**(2026-08-31 사용자:
    /// *"앱이 그 전에 suspend되어 있던 화면 상태로 suspend"*). `RootView`가 넣고 `RootView`가 쓴다.
    var tabBeforeHotkey: AppTab?

    /// **핫키가 앱을 새로 깨운 것으로 보이나** — ⚠️ **추정이다**(아래).
    ///
    /// 사용자 결정(2026-08-31): *"앱이 그 전에 suspend되어 있던 화면 상태로 suspend.
    /// 아예 앱이 exit 상태였다면 exit상태로."* → **깨운 것이면 끝내고, 이미 떠 있었으면 내려놓는다.**
    ///
    /// ⛔ **「앱이 그 전에 떠 있었나」를 딱 잘라 아는 공개 API가 없다.** 그래서 **프로세스가 뜬 뒤
    /// 얼마나 지났는지**로 가른다 — 콜드 런치면 수집 요청이 **거의 즉시** 오고, 이미 쓰고 있었다면
    /// 그만큼 시간이 지나 있다.
    /// ⚠️ **문턱 3초는 잰 값이 아니라 고른 값이다**(추정). **틀리는 방향이 둘 다 가볍다:**
    /// **① 앱을 켠 직후(3초 안) 핫키를 누르면** 깨운 것으로 봐 **끝낸다**(사용자가 다시 열면 된다) ·
    /// **② 시작이 3초를 넘게 걸리면** 이미 떠 있던 것으로 봐 **내려놓는다**(끝나지 않는다).
    /// ⛔ **`exit(0)` 쪽이 더 비싼 오판이므로**(크래시로 기록된다) 문턱을 **짧게** 잡았다.
    var likelyWokenByHotkey: Bool {
        Date().timeIntervalSince(Self.processStarted) < 3.0
    }

    /// **수집이 [취소하기]로 닫혔나** — `RootView`가 「앱 밖으로」를 할지 정하는 데 쓴다.
    /// ⛔ **`<`로 닫히면 이 값이 안 켜진다** — `<`는 **앱 안에 머무는** 뜻이다.
    /// ⚠️ **RootView가 쓰고 나서 반드시 내린다** — 안 내리면 다음 닫힘에서 앱이 나가 버린다.
    var cancelledOut = false

    /// ★ **애니메이션 없이 띄운다** (2026-08-31 사용자: *"지금은 핫키 눌러서 앱에 진입하면 첫 화면
    /// 띄운 후 수집 화면으로 들어오지만 내 의도대로라면 바로 수집 화면으로 들어와야 해."*)
    ///
    /// ⚠️ **첫 프레임이 목록인 것 자체는 못 없앤다** — 앱이 떠야 인텐트가 돌고, 그 뒤에 시트가 뜬다.
    /// **없앨 수 있는 것은 「미끄러져 올라오는 동작」**이고, 그것을 없애면 **목록이 스쳐 보이는 시간이
    /// 애니메이션 길이(≈0.35초)만큼 줄어든다.** ⛔ **「바로」의 나머지는 앱 시작 시간이다.**
    func requestCapture() {
        Self.probe("intent")
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { showCapture = true }
    }

    // MARK: ⏸ 재는 장치 (2026-08-31 · **다 재면 지운다**)
    //
    // ## 왜 있나 — **문(`RootView.launchGate`)의 값을 짐작으로 두 번 정할 수 없다**
    // 핫키로 들어올 때 목록이 스치는 것을 **120ms 문**으로 막으려 했는데 **여전히 스쳤다**
    // (사용자 판정 2026-08-31). 그러면 **인텐트가 그보다 늦게 오는 것**인데,
    // ⛔ **얼마나 늦는지는 액션 버튼을 눌러야 알 수 있고 그것은 사용자가 하는 일이다**(항시 규칙 7).
    // ★ **그래서 앱이 스스로 적게 하고, 그 파일을 맥으로 가져와 읽는다**(`CLAUDE.md` ⓒ).
    //
    // ⚠️ **이것은 「쓰는 도구」가 아니라 「한 번 재는 장치」다** — 값을 얻으면 **이 블록과 호출을 지운다.**
    // ⛔ **상태를 안 바꾼다** — 파일 하나에 줄만 덧붙인다(append-only · 앱 동작에 영향 0).

    /// 프로세스가 뜬 뒤 지난 밀리초를 한 줄 적는다. 실패하면 조용히 지나간다(재는 장치가 앱을 막지 않게).
    static func probe(_ what: String) {
        let ms = Int(Date().timeIntervalSince(processStarted) * 1000)
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true) else { return }
        let dir = base.appendingPathComponent("SecondBrain", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("launch-probe.log")
        let line = "\(what) +\(ms)ms\n"
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
