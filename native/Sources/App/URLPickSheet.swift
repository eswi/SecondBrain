#if os(iOS)
import SwiftUI
import SecondBrainCore

/// **URL이 둘 이상일 때 고르는 목록** — 네모를 누르면 뜬다 (2026-08-25 사용자 결정 · 설계 §3-Z-8).
///
/// ## ⛔ 왜 브라우저 밖인가
/// 앱 안 보기(`SFSafariViewController`)에는 **단추를 얹을 자리가 API에 없다**(헤더로 확인했다 —
/// `delegate`·`configuration`·`dismissButtonStyle`·색 둘뿐이고 색은 iOS 26에서 deprecated다).
/// 그래서 넘기는 자리는 **브라우저 밖**이어야 한다.
///
/// **안 고른 길:** `WKWebView`로 브라우저를 직접 만들어 그 위에 `‹` `›`를 얹는 것.
/// 사용자가 그 방법을 물었고, **대가를 보고 물렀다** — ⛔ **사파리에 해둔 로그인이 안 따라온다**
/// (`SFSafariViewController`는 사파리와 쿠키를 공유하고 `WKWebView`는 자기 저장소를 쓴다) ·
/// 주소 표시·뒤로·새로고침을 다 만들어야 한다 · **내가 만든 브라우저를 유지해야 한다.**
///
/// ## 화면에 나오는 말이 없다 — 새로 짓지 않았다 (항시 규칙 6)
/// **제목도 버튼도 없다.** `MediaAddSheet`와 **같은 꼴**(줄만 있는 시트)이고,
/// 줄에 보이는 것은 **URL 그 자체**다(내가 지은 말이 아니라 데이터다).
///
/// ⚠️ **하나뿐일 때는 이 시트가 안 뜬다** — 바로 열린다(이미 판정을 통과한 동작을 그대로 뒀다).
struct URLPickSheet: View {
    let urls: [String]
    /// 고른 URL — ⚠️ **시트가 닫힌 뒤** 브라우저를 연다(겹쳐 띄우면 iOS가 둘째를 무시한다).
    var onPick: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(urls.enumerated()), id: \.offset) { i, u in
                Button { onPick(u) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "link")
                            .font(.system(size: 18))
                            .frame(width: 26)
                            .foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            // 짧은 이름을 굵게 — 네모에 보이는 것과 **같은 말**이라 눈이 잇는다
                            if let s = URLAsset.shortName(u) {
                                Text(s).font(.body).foregroundStyle(Palette.textPrimary)
                            }
                            // 그 아래 URL 전체를 한 줄로 — 둘을 가르는 것은 대개 뒷부분이다
                            Text(u).font(.caption).foregroundStyle(Palette.textSecondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i != urls.count - 1 { Divider().padding(.leading, 56) }
            }
        }
        .padding(.top, 8)
        .presentationDetents([.height(CGFloat(urls.count) * 56 + 40)])
    }
}

/// `sheet(item:)`에 넘기려면 `Identifiable`이 필요하다.
struct URLPick: Identifiable {
    let urls: [String]
    var id: String { urls.joined(separator: "|") }
}
#endif
