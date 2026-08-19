import SwiftUI
import CoreLocation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// **자료를 화면에 올리기 위한 플랫폼 갈래 둘** — 설계 `docs/native/media-icloud-design.md` §7.
///
/// ## 왜 이 파일이 생겼나
///
/// `DetailView.photoRow`가 `#if os(iOS)`로 **통째로** 감싸여 있었고 `#else`는 **무조건
/// 「이 기기엔 없음」**을 보였다. 그래서 macOS에서는 파일이 **실제로 도착해 있는데도** 없다고 말했다 —
/// **iOS의 미다운로드와 달리 영구히 틀린다.**
/// `FolderLink`가 세운 원칙(*"연결이 끊긴 것과 비어 있는 것을 절대 같게 보이지 않는다"*)이
/// 문제 삼는 것과 **같은 종류**다(§6·§7).
///
/// **막고 있던 것은 판정이 아니라 타입 둘뿐이었다** — 이미지 로딩(`UIImage`)과 지도 앱 열기(`UIApplication`).
/// 그 둘만 여기서 갈라 두면 **화면 코드에는 `#if`가 없어진다.**
///
/// ⚠️ **촬영은 여전히 iOS 전용이다**(`PhotoStore.saveCaptured`) — **이번 범위 밖**(§7의 표).
/// **보는 것과 만드는 것을 가르는 것**이 이 파일의 경계다.
enum PlatformMedia {

    /// 파일에서 이미지를 읽어 SwiftUI `Image`로. 못 읽으면 nil(→ 화면은 「없음」 안내로 간다).
    ///
    /// **nil이 「파일이 없다」만 뜻하지 않는다** — 깨진 파일도 nil이다. 화면은 둘을 같게 다뤄도 된다:
    /// **둘 다 「이 기기에서 볼 수 없다」**이고, 그것이 사용자가 할 수 있는 일(다시 시도)과 맞는다.
    static func image(contentsOfFile path: String) -> Image? {
        #if os(iOS)
        guard let ui = UIImage(contentsOfFile: path) else { return nil }
        return Image(uiImage: ui)
        #elseif os(macOS)
        guard let ns = NSImage(contentsOfFile: path) else { return nil }
        return Image(nsImage: ns)
        #else
        return nil
        #endif
    }

    /// 좌표를 **지도 앱**에서 연다. 문구·버튼은 화면 쪽에 있고 여기는 **여는 일만** 한다.
    ///
    /// URL 꼴은 두 플랫폼이 같다(`maps.apple.com`) — 다른 것은 **누가 여는가**뿐이다.
    ///
    /// `@MainActor`인 이유: `UIApplication.shared`가 메인 액터에 묶여 있다.
    /// 부르는 자리는 버튼 동작(뷰 안)이라 **이미 메인**이다 — 제약이 아니라 사실을 적은 것이다.
    @MainActor
    static func openInMaps(_ coord: CLLocationCoordinate2D) {
        guard let u = URL(string: "http://maps.apple.com/?ll=\(coord.latitude),\(coord.longitude)")
        else { return }
        #if os(iOS)
        UIApplication.shared.open(u)
        #elseif os(macOS)
        NSWorkspace.shared.open(u)
        #endif
    }
}
