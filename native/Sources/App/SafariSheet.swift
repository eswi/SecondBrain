import Foundation

#if os(iOS)
import SwiftUI
import SafariServices

/// **앱 안 보기** — URL 네모를 누르면 이것으로 연다 (2026-08-24 사용자 결정 · 설계 §3-Z-2 G).
///
/// ⛔ **사파리로 나가지 않는다** — 닫으면 **바로 기억으로 돌아온다.**
/// 안 고른 것: ㉯ 사파리로 나간다(앱을 떠난다) · ㉰ 뷰어에 들어가 그 안에서 열기(두 번 눌러야 한다).
///
/// ⚠️ **사진·음성의 뷰어(`MediaViewer`)와 다른 길이다** — 그래서 **`‹` `›`로 넘기기가 없다.**
/// URL이 여럿인 기억에서 둘째 URL을 보려면 **네모를 다시 눌러야 한다.**
/// ⏸ **그것을 어떻게 할지는 아직 안 정했다**(설계 §3-Z-6 뒤에 붙을 물음).
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: cfg)
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
#endif

/// `sheet(item:)`에 넘기려면 `Identifiable`이 필요하다 — `URL`은 아니라서 감싼다.
struct OpeningURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
