import SwiftUI
#if os(iOS)
import UIKit

/// **앱을 띄울 때 준 「옵션」을 첫 프레임보다 먼저 읽는 자리** (2026-08-31 사용자 결정).
///
/// 사용자: *"핫키로 띄울 때는 command line option처럼 invoke Option을 주게 하고, 우리는 그런 특정
/// 옵션을 달아서 앱을 띄울 때는 다른 화면 안 보이고 바로 수집 화면으로 직행하도록 프로그래밍하면
/// 안 되나? … 시간을 재는 방식을 써야 하는거야?"*
///
/// ★★ **안 써야 한다 — 사용자가 맞았다.** iOS에서 「command line option」에 해당하는 것이
/// **URL 스킴**이고, 그것은 **`didFinishLaunchingWithOptions`의 `launchOptions[.url]`로
/// 첫 프레임보다 먼저** 온다. **그래서 시간을 잴 필요가 없다.**
///
/// | 길 | 언제 알 수 있나 | 목록이 스치나 |
/// |---|---|---|
/// | **`secondbrain://capture`**(이것) | **첫 프레임 전** — 런치 옵션 | **안 스친다** |
/// | App Intent(`openAppWhenRun`) | 앱이 뜬 **뒤** `perform()` | **스친다** — 사전 신호가 없다 |
///
/// ⛔ **App Intent는 그대로 남겨 뒀다**(하위호환) — 액션 버튼을 다시 묶기 전까지 그 길로 들어오면
/// **여전히 목록이 스친다.** 그것은 **못 고치는 것이 아니라 그 길에 옵션이 없는 것이다.**
/// ⚠️ **옛 시도(지우지 않고 적어 둔다):** 시트 애니메이션 끄기 → **부족했다**(첫 프레임이 목록) ·
/// **120ms 문으로 덮기** → **여전히 스쳤다**(인텐트가 그보다 늦게 온다). **둘 다 시간을 짐작한 것이다.**
final class AppLaunchOptions: NSObject, UIApplicationDelegate {
    /// 우리가 쓰는 스킴과 「바로 수집」을 뜻하는 자리.
    static let scheme = "secondbrain"
    static let captureHost = "capture"

    /// ★★ **첫 프레임 전에 URL을 보는 자리** — scene이 만들어질 때 불린다(UI는 아직 없다).
    ///
    /// ⚠️ **`didFinishLaunchingWithOptions`의 `launchOptions[.url]`은 iOS 26에서 deprecated다**
    /// (*"Use UIScene lifecycle and UIScene.ConnectionOptions.URLContexts instead"*).
    /// **이 자리가 그 「대신」이고, 여전히 첫 프레임 전이다.**
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        Self.handle(options.urlContexts)
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    /// `secondbrain://capture` 면 수집을 켠다. **모르는 URL은 조용히 무시한다**(관용적 · 설계 §6).
    static func handle(_ contexts: Set<UIOpenURLContext>) {
        for c in contexts where isCapture(c.url) { CaptureLauncher.shared.requestCapture(); return }
    }

    /// 앱이 떠 있는 동안 들어오는 길은 SwiftUI의 `onOpenURL`이 받는다(`RootView`).
    /// ⚠️ **그 길에는 「목록이 스친다」 문제가 없다** — 이미 화면이 있다.
    static func handle(_ url: URL) {
        guard isCapture(url) else { return }
        CaptureLauncher.shared.requestCapture()
    }

    private static func isCapture(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme else { return false }
        // `secondbrain://capture` 와 `secondbrain:///capture` 둘 다 받는다 — 사람이 손으로 적는 값이다.
        return url.host?.lowercased() == captureHost
            || url.path.lowercased().contains(captureHost)
    }
}
#endif

/// 네이티브 v1 앱 진입점 (iOS·macOS 공유). 루트 = 탭바(RootView).
@main
struct SecondBrainApp: App {
    #if os(iOS)
    /// ⛔ **이 어댑터가 있어야 런치 옵션을 볼 수 있다** — SwiftUI만으로는 `onOpenURL`뿐이고
    /// 그것은 **첫 프레임 뒤**에 온다.
    @UIApplicationDelegateAdaptor(AppLaunchOptions.self) private var launchOptions
    #endif

    init() {
        // 일회성 정리: 제거된 '분류 관리 → 재설계 후보'(§7 — 분류는 코드 고정)의 UserDefaults 키만 지운다.
        // 후보 아이디어는 classification-redesign-open-questions.md로 이관·보존됨(2026-07-26).
        // 이 키만 대상 — sb_folder_bookmark·sb_hlc_last 등 핵심 키는 절대 안 건드린다.
        UserDefaults.standard.removeObject(forKey: "reclass.candidates.v1")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
