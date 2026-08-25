#if os(iOS)
import Foundation
import UIKit
import WebKit

/// **그 페이지를 실제로 그려서 첫 화면을 찍는다** (2026-08-25 사용자 결정 · 설계 §3-Z-12).
///
/// ## ★ 사용자의 원래 1순위였다
/// 2026-08-24에 사용자가 물었다: *"그 URL에 접속해서 그 URL이 제시하는 아이콘이나 대표 이미지 하나
/// 뽑을 수 없을까? **페이지 스크린샷은 어렵다면서?**"* — **어렵다고 알고 있어서 대표 이미지로 물러선 것**이고,
/// 2026-08-25에 **API가 있다는 것을 확인하고 되돌아왔다**(`WKWebView.takeSnapshot`, iOS 11+).
/// ⛔ **그래서 순서에서 맨 앞이다** — 캡쳐 → 대표 그림 → 아이콘 → ①.
///
/// ## ⛔ 어려운 자리는 API가 아니라 이 다섯이었다 — 여기서 하나씩 다룬다
/// | | 무엇 | 어떻게 했나 |
/// |---|---|---|
/// | ① | **언제 찍나** — 「로드 끝」 판정이 없다 | `didFinish` 뒤 **`settleSeconds` 더 기다린다**(늦게 그려지는 것) · 전체 **`timeoutSeconds`** |
/// | ② | **빈 화면을 찍는다** | **단색 검사** — 거의 한 색이면 **버리고 다음 후보로** 넘긴다 |
/// | ③ | **페이지는 세로로 아주 길다** | **위쪽 정사각형만** 찍는다(`WKSnapshotConfiguration.rect`) — 62pt 네모에 꽉 찬다 |
/// | ④ | **무겁다** | **붙일 때 한 번만** 돈다(§3-Z-2 D) — 목록·상세를 여는 자리에서는 절대 안 돈다 |
/// | ⑤ | **광고·쿠키 배너가 찍힌다** | ⚠️ **못 막는다.** 그것이 그 페이지의 첫 화면이다 — **사실대로 찍는다** |
///
/// ## ⚠️ 보이지 않는 웹뷰는 그려지지 않는다 — **화면에 붙여야 한다**
/// 화면 계층에 없는 `WKWebView`는 레이아웃·렌더링을 건너뛰어 **스냅샷이 빈다.**
/// 그래서 **창에 붙이되 거의 투명하게**(`alpha`를 0으로 두면 렌더링을 건너뛸 수 있어 아주 작게 남긴다)
/// 두고, **손짓을 안 받게** 한 뒤 **끝나면 반드시 떼어낸다.**
@MainActor
enum URLPageCapture {

    /// 폰 폭으로 그린다 — **폰에서 보이는 그대로**가 찍히게. 정사각형이라 세로도 같은 값이다.
    static let side: CGFloat = 402
    /// `didFinish` 뒤 더 기다리는 시간 — 늦게 그려지는 것(글꼴·지연 로딩)을 위해.
    static let settleSeconds: Double = 1.2
    /// 전체 시간 제한 — 이보다 길면 포기하고 다음 후보로 간다.
    static let timeoutSeconds: Double = 12

    /// 첫 화면을 찍어 JPEG로 돌려준다. **못 찍었으면 nil**(그러면 대표 그림 갈래로 내려간다).
    static func firstScreen(of url: URL) async -> Data? {
        guard let host = hostWindow() else { return nil }

        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        web.isOpaque = true
        web.backgroundColor = .white          // 투명하면 스냅샷 뒷면이 검게 나온다
        web.alpha = 0.01                      // ⚠️ 0이면 렌더링을 건너뛸 수 있다
        web.isUserInteractionEnabled = false
        host.addSubview(web)
        defer { web.removeFromSuperview() }

        let waiter = LoadWaiter()
        web.navigationDelegate = waiter

        var req = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        // 폰 사파리와 같은 꼴로 묻는다 — 봇으로 보고 빈 것을 주는 사이트가 있다.
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
                     + "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        web.load(req)

        // ① 로드가 끝나기를 기다린다 — 실패하면 그래도 한 번 찍어 본다(부분 렌더링이 있을 수 있다).
        await waiter.wait(timeout: timeoutSeconds)
        // 늦게 그려지는 것을 기다린다. ⚠️ `try?`로 취소를 삼키지 않는다(2026-08-24에 그것으로 결함이 났다).
        do { try await Task.sleep(nanoseconds: UInt64(settleSeconds * 1_000_000_000)) }
        catch { return nil }        // 취소됐다 — 찍지 않는다

        // ③ 위쪽 정사각형만
        let cfg = WKSnapshotConfiguration()
        cfg.rect = CGRect(x: 0, y: 0, width: side, height: side)
        cfg.afterScreenUpdates = true

        guard let img = try? await web.takeSnapshot(configuration: cfg) else { return nil }
        // ② 빈 화면이면 버린다 — 그러면 대표 그림 갈래로 내려간다
        guard !looksBlank(img) else { return nil }
        return img.jpegData(compressionQuality: 0.85)
    }

    // MARK: 안쪽

    private static func hostWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ??
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first
    }

    /// **거의 한 색인가** — 로드 전에 찍으면 흰 화면이나 빈 화면이 나온다.
    ///
    /// 8×8로 줄여 **밝기의 펴짐**을 본다. ⚠️ **문턱은 낮게 잡는다** —
    /// 「글자 몇 줄뿐인 담백한 페이지」를 버리면 안 된다. **정말 한 색인 것만** 걸러낸다.
    private static func looksBlank(_ img: UIImage) -> Bool {
        let n = 8
        guard let cg = img.cgImage else { return false }
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8,
                                  bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))

        var lum = [Double]()
        for i in stride(from: 0, to: px.count, by: 4) {
            lum.append(0.2126 * Double(px[i]) + 0.7152 * Double(px[i+1]) + 0.0722 * Double(px[i+2]))
        }
        guard !lum.isEmpty else { return false }
        let mean = lum.reduce(0, +) / Double(lum.count)
        let sd = (lum.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lum.count)).squareRoot()
        return sd < 3.0          // 0에 가까우면 한 색이다
    }
}

/// `didFinish`/`didFail`이 왔나만 들고 있는 작은 대리자.
///
/// ⚠️ **기다리는 방식을 「이어주기(continuation)」에서 「되묻기(polling)」로 바꿨다** (2026-08-25).
/// ⛔ 이어주기 꼴은 Swift의 격리 검사를 통과하지 못했다
/// (`pattern that the region-based isolation checker does not understand how to check`).
/// ★ **되묻기가 더 튼튼하다** — 리다이렉트로 `didFinish`가 여러 번 와도, 아무것도 안 와도 **같은 길로 끝난다.**
@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    /// 로드가 끝났나(성공이든 실패든). ⚠️ **실패도 「끝」이다** — 부분 렌더링이 있을 수 있어 그래도 찍어 본다.
    private(set) var finished = false

    /// **0.1초마다 되묻는다.** 끝나면 바로 돌아오고, 시간 제한을 넘기면 그냥 돌아온다
    /// (⛔ 실패로 보지 않는다 — 그 뒤에 한 번 찍어 보고 빈 화면이면 그때 버린다).
    func wait(timeout: Double) async {
        let ticks = max(1, Int(timeout / 0.1))
        for _ in 0..<ticks {
            if finished { return }
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
        }
    }

    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { finished = true }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { finished = true }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { finished = true }
}
#endif
