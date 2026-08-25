#if os(iOS)
import Foundation
import UIKit
import CryptoKit
import SecondBrainCore

/// **URL 자료의 미리보기 그림** — 그 사이트에서 한 번 뽑아 **기기에만** 둔다.
///
/// ## ★ 이것은 자료가 아니라 **캐시**다 (2026-08-24 사용자 결정 · 설계 §3-Z-2 E)
/// **다시 뽑을 수 있으니 원본이 아니다.** 그래서:
/// - **iCloud에 안 올린다** — 용량 걱정이 아예 안 생긴다(위키백과 og:image는 **680KB**였다).
/// - **병합·검산에 안 든다** — 포인터가 없으므로 「누락·고아·겹침」 셋의 대상이 아니다.
/// - **지워도 안전하다** — 없으면 네모가 ①(아이콘 + 도메인 이름)으로 그려진다.
/// ⚠️ **사용자가 직접 붙인 그림은 반대다 — 그것은 자료(불변)**이고 `photo` 갈래로 간다(§3-Z-2 F).
///
/// ## ⛔ 연결은 **붙이는 그 자리에서 한 번만** (사용자 결정 · §3-Z-2 D)
/// **목록을 여는 것만으로는 아무 사이트도 연결하지 않는다.** 이 앱이 지금까지 지켜온 것을
/// 넘는 첫 자리라(사용자가 안 누른 외부 연결) **횟수를 한 번으로 묶었다.**
/// **실패해도 다시 시도하지 않는다** — 그것을 보장하려고 **빈 표시 파일(`.miss`)**을 남긴다.
/// ⛔ **그 파일이 없으면 「아직 안 해봤다」와 「해봤는데 없다」가 구분되지 않아** 열 때마다 연결하게 된다.
///
/// ## 뽑는 순서 — **쟀다** (2026-08-24 표본 여덟 · §3-Z-4)
/// ★ **맨 앞은 「페이지 첫 화면 캡쳐」다**(2026-08-25 · §3-Z-12 · `URLPageCapture`) —
/// **사용자의 원래 1순위**였고 「어렵다」로 물러서 있었다. 그 아래가 아래 넷이다.
/// `og:image` → `twitter:image` → `apple-touch-icon` → `link rel=icon`.
/// **og:image가 가장 잘 잡히고(6/8) 해상도가 충분하다.** 아이콘은 정사각이지만 **최대 160px로 모자라다**
/// (62pt는 @3x에 186px). ⛔ **SVG·ICO는 `UIImage`가 못 읽을 수 있다** —
/// **디코드가 실패하면 다음 후보로 넘어가고, 다 실패하면 ①로 떨어진다.**
enum URLPreview {

    /// 긴 변을 이 픽셀로 맞춰 저장한다 — 62pt @3x = **186px**(§3-Z-4에서 쟀다).
    private static let maxPixel: CGFloat = 186

    /// ★★ **너무 긴 그림은 쓰지 않는다 — 문턱 3:1** (2026-08-24 사용자 결정 · 설계 §3-Z-7)
    ///
    /// ⛔ **실기기 판정에서 나온 결함이다.** 자르지 않고 온전히 넣기로 정했는데(§3-Z-2 C),
    /// **가로로 아주 긴 그림은 온전히 넣으니 너무 작아져 못 읽혔다** —
    /// 사용자: *"가로로 긴 글자 보드가 아이콘 형태라서 확대해야 글자가 보임."*
    /// 실데이터 `wowanalytica`의 대표 그림은 **367×75(4.89:1)**여서 62pt 네모에서 **높이 11.1pt**가 된다.
    /// **앱이 쓰는 가장 작은 글자가 7.13pt**이니 그 안의 글자는 애초에 읽힐 수 없었다.
    ///
    /// ★ **자르는 쪽으로 되돌리지 않았다** — 자르면 「ANALY」처럼 글자 일부만 남는데
    /// **그것이 애초에 자르지 않기로 한 이유였다.** 대신 **쓸 수 있는 그림의 조건**을 더했다:
    /// **문턱을 넘으면 다음 후보로 넘어간다**(아이콘 → ①). `wowanalytica`는 정사각 아이콘(57×57)이 있어
    /// **그 금색 마크가 네모를 꽉 채운다.**
    ///
    /// **3:1은 사용자가 고른 값이다**(느슨한 쪽) — 짧은 변이 **18.2pt** 이상이면 쓴다.
    /// 오늘 표본에서 **`wowanalytica`(4.89)만 탈락**하고 wikipedia(2.20)·github(2.00)·
    /// questionablyepic(1.77)·youtube(1.00)는 통과한다.
    /// ⚠️ **18.2pt가 읽히는지는 안 쟀다** — 표본에 그 근처가 없었다(가장 가까운 것이 2.20:1 = 24.7pt).
    /// 같은 말이 다시 나오면 **그때는 그 비율의 표본으로 잰다.**
    static let maxAspect: CGFloat = 3.0

    /// 이 그림을 네모에 쓸 수 있나 — **비율만 본다.**
    ///
    /// ⚠️ **뽑는 쪽과 그리는 쪽이 둘 다 이것을 부른다.** 뽑는 쪽만 고치면
    /// ⛔ **이미 붙어 있는 자료가 안 고쳐진다** — 캐시에 옛 그림이 있고 **결정 D(붙일 때 한 번만)** 때문에
    /// 다시 연결할 계기가 없다. **그리는 쪽이 안전망이다.**
    static func usable(_ img: UIImage) -> Bool {
        let w = img.size.width, h = img.size.height
        guard w > 0, h > 0 else { return false }
        return max(w, h) / min(w, h) <= maxAspect
    }

    // MARK: 자리

    private static func dir() -> URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true) else { return nil }
        let d = base.appendingPathComponent("SecondBrain/url-preview", isDirectory: true)
        if !fm.fileExists(atPath: d.path) {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    /// ★ **뽑는 규칙의 판.** 규칙이 바뀌면 이 값을 올린다 — 그러면 옛 캐시가 **안 읽히고 다시 뽑힌다.**
    ///
    /// ⛔ **없으면 규칙을 고쳐도 이미 붙은 URL이 새 규칙을 못 받는다** — 캐시 이름이 URL 해시라서
    /// **같은 URL이 「이미 해봤다」로 걸려 다시 안 뽑히기 때문이다**(2026-08-25에 실제로 그랬다).
    /// **결정 D(붙일 때 한 번만)와 규칙 변경이 부딪히는 자리이고, 판이 그 매듭이다.**
    ///
    /// - `a3` = **비율 문턱 3:1**을 적용한 판(2026-08-25 · 설계 §3-Z-7).
    ///   그 앞 판(문턱 없음)의 파일은 **읽지 않고 지운다.**
    private static let rule = "a3"

    /// 캐시 이름은 **URL의 해시 + 규칙 판**이다 — ⚠️ 자료 id가 아니다.
    /// **같은 URL을 두 기억에 붙이면 한 번만 받는다**(캐시니까 공유해도 된다).
    private static func key(_ url: String) -> String {
        let d = SHA256.hash(data: Data(url.utf8))
        let h = d.compactMap { String(format: "%02x", $0) }.joined().prefix(32)
        return "\(h)-\(rule)"
    }

    /// 옛 판이 남긴 파일을 지운다 — 기기에만 있는 캐시라 **지워도 안전하다.**
    /// ⚠️ 뽑을 때 한 번만 부른다(그리는 자리에서 파일을 지우지 않는다).
    private static func sweepOldRules(_ url: String) {
        guard let d = dir() else { return }
        let h = SHA256.hash(data: Data(url.utf8)).compactMap { String(format: "%02x", $0) }.joined().prefix(32)
        guard let all = try? FileManager.default.contentsOfDirectory(atPath: d.path) else { return }
        for n in all where n.hasPrefix(String(h)) && !n.hasPrefix("\(h)-\(rule)") {
            try? FileManager.default.removeItem(at: d.appendingPathComponent(n))
        }
    }

    private static func imageFile(_ url: String) -> URL? {
        dir()?.appendingPathComponent("\(key(url)).jpg")
    }

    private static func missFile(_ url: String) -> URL? {
        dir()?.appendingPathComponent("\(key(url)).miss")
    }

    // MARK: 읽기 — 그리는 쪽이 쓴다 (네트워크를 안 부른다)

    /// 이미 받아 둔 미리보기. **없으면 nil이고 네모는 ①로 그려진다.**
    /// ⛔ **이 함수는 절대 연결하지 않는다** — 목록을 그리는 자리에서 불린다.
    static func cached(_ url: String) -> UIImage? {
        guard let f = imageFile(url), FileManager.default.fileExists(atPath: f.path) else { return nil }
        guard let img = UIImage(contentsOfFile: f.path) else { return nil }
        // ⛔ **문턱을 넘는 그림은 없는 것으로 본다** — 그러면 네모가 ①로 그려진다.
        //    **이미 붙어 있던 자료가 이 줄로 고쳐진다**(캐시를 지우지 않아도 된다 · 위 `usable` 참고).
        return usable(img) ? img : nil
    }

    /// 이미 한 번 해봤나 — 성공(그림)이든 실패(`.miss`)든.
    static func attempted(_ url: String) -> Bool {
        guard let i = imageFile(url), let m = missFile(url) else { return false }
        let fm = FileManager.default
        return fm.fileExists(atPath: i.path) || fm.fileExists(atPath: m.path)
    }

    // MARK: 뽑기 — **붙일 때 한 번만 불린다**

    /// 그 사이트에 한 번 연결해 대표 그림을 받아 캐시에 둔다.
    /// **이미 해본 URL이면 아무것도 안 한다**(연결하지 않는다).
    static func fetchOnce(_ raw: String) async {
        guard let normalized = URLAsset.normalized(raw),
              let pageURL = URL(string: normalized) else { return }
        sweepOldRules(normalized)                  // 옛 판 찌꺼기를 먼저 치운다
        guard !attempted(normalized) else { return }

        var got: Data?

        // ★ ① **페이지를 실제로 그려서 첫 화면을 찍는다** — 사용자의 1순위(§3-Z-12).
        //   ⛔ **못 찍으면 조용히 아래 갈래로 내려간다** — 빈 화면·시간초과·차단이 다 여기서 걸러진다.
        //   ⚠️ **정사각형이라 비율 문턱(§3-Z-7)을 늘 통과한다** — 페이지 전체를 안 찍는 이유가 그것이다.
        if let shot = await URLPageCapture.firstScreen(of: pageURL), UIImage(data: shot) != nil {
            got = shot
        }
        // ⚠️ **임시 진단** — 캡쳐가 왜 안 됐나를 파일로 남긴다(2026-08-25).
        //    맥에서 `devicectl device copy from`으로 가져와 읽는다. ⏸ **원인이 닫히면 걷어낸다.**
        if got == nil, let d = dir() {
            let why = await URLPageCapture.lastFailure ?? "nil"
            let line = "\(why)\t\(normalized)\n"
            let f = d.appendingPathComponent("capture-why.log")
            if let h = try? FileHandle(forWritingTo: f) {
                h.seekToEndOfFile(); try? h.write(contentsOf: Data(line.utf8)); try? h.close()
            } else {
                try? Data(line.utf8).write(to: f, options: .atomic)
            }
        }

        // ② 못 찍었으면 그 페이지가 스스로 내놓는 그림을 찾는다(2026-08-24에 쟀던 순서 그대로).
        if got == nil, let html = await fetchText(pageURL) {
            for candidate in candidates(in: html, base: pageURL) {
                // ⛔ **디코드만으로 채택하지 않는다** — 비율이 문턱을 넘으면 **다음 후보로 넘어간다**
                //    (2026-08-24 사용자 결정). 그래서 긴 글자판 대신 정사각 아이콘이 잡힌다.
                guard let d = await fetchData(candidate), let img = UIImage(data: d) else { continue }
                if usable(img) { got = d; break }
            }
        }

        if let d = got, let img = UIImage(data: d), let shrunk = downscale(img),
           let f = imageFile(normalized) {
            try? shrunk.write(to: f, options: .atomic)
        } else if let m = missFile(normalized) {
            // ⛔ **못 뽑았다는 것도 남긴다** — 안 남기면 열 때마다 다시 연결한다(결정 D 위반).
            try? Data().write(to: m, options: .atomic)
        }
    }

    // MARK: 안쪽

    private static func request(_ u: URL) -> URLRequest {
        var r = URLRequest(url: u, timeoutInterval: 8)
        // 사파리와 같은 꼴로 묻는다 — 봇으로 보고 빈 것을 주는 사이트가 있다
        // (2026-08-24 표본에서 `brunch.co.kr`가 아무것도 안 줬다 — ⚠️ 없는 것인지 막은 것인지 **못 갈랐다**).
        r.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
                   + "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                   forHTTPHeaderField: "User-Agent")
        return r
    }

    private static func fetchText(_ u: URL) async -> String? {
        guard let (d, _) = try? await URLSession.shared.data(for: request(u)) else { return nil }
        // 머리만 읽으면 된다 — `<head>`의 meta가 목표다. 큰 문서를 통째로 문자열로 만들지 않는다.
        let head = d.prefix(300_000)
        return String(data: head, encoding: .utf8) ?? String(decoding: head, as: UTF8.self)
    }

    private static func fetchData(_ u: URL) async -> Data? {
        guard let (d, _) = try? await URLSession.shared.data(for: request(u)) else { return nil }
        return d.count > 0 && d.count < 8_000_000 ? d : nil
    }

    /// 후보를 순서대로 — **쟀던 순서 그대로**(§3-Z-4).
    /// ⚠️ HTML을 정규식으로 읽는다 — `head`의 meta 한 줄을 찾는 데는 충분하고, **틀리면 ①로 떨어진다.**
    private static func candidates(in html: String, base: URL) -> [URL] {
        var out: [URL] = []
        for pattern in [
            #"<meta[^>]+(?:property|name)\s*=\s*["']og:image(?::url)?["'][^>]*>"#,
            #"<meta[^>]+(?:property|name)\s*=\s*["']twitter:image(?::src)?["'][^>]*>"#,
            #"<link[^>]+rel\s*=\s*["'][^"']*apple-touch-icon[^"']*["'][^>]*>"#,
            #"<link[^>]+rel\s*=\s*["'][^"']*icon[^"']*["'][^>]*>"#,
        ] {
            guard let tag = firstMatch(pattern, in: html) else { continue }
            guard let raw = attribute("content", in: tag) ?? attribute("href", in: tag) else { continue }
            if let u = resolve(raw, base: base) { out.append(u) }
        }
        return out
    }

    private static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s) else { return nil }
        return String(s[r])
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let m = firstMatch(#"\#(name)\s*=\s*["']([^"']*)["']"#, in: tag) else { return nil }
        guard let q = m.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        let rest = m[m.index(after: q)...]
        guard let end = rest.lastIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        let v = String(rest[rest.startIndex..<end])
        return v.isEmpty ? nil : v
    }

    /// ⚠️ **쟀을 때 나온 함정 셋을 여기서 다 처리한다**(§3-Z-4):
    /// **프로토콜 상대**(`//i.namu.wiki/…`) · **상대 경로**(`/img/x.png`) · **`&amp;` 이스케이프**(위키백과).
    private static func resolve(_ raw: String, base: URL) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.hasPrefix("data:") else { return nil }   // `data:,`(빈 것)가 실제로 있었다
        s = s.replacingOccurrences(of: "&amp;", with: "&")
             .replacingOccurrences(of: "&#38;", with: "&")
        if s.hasPrefix("//") { s = (base.scheme ?? "https") + ":" + s }
        return URL(string: s, relativeTo: s.hasPrefix("http") ? nil : base)?.absoluteURL
    }

    /// 긴 변을 186px로 — **비율은 유지한다**(자르지 않는다 · 결정 C).
    private static func downscale(_ img: UIImage) -> Data? {
        let w = img.size.width, h = img.size.height
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, maxPixel / max(w, h))
        let size = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        let r = UIGraphicsImageRenderer(size: size)
        let out = r.image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.85)
    }
}
#endif
