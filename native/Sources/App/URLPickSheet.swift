#if os(iOS)
import SwiftUI
import SecondBrainCore

/// **URL이 둘 이상일 때 고르는 목록** — 네모를 누르면 **그 네모에 붙어 아래로 펼쳐진다**
/// (2026-08-25 사용자 결정 · 설계 §3-Z-8 · §3-Z-9).
///
/// ## ★ 처음엔 화면 아래에서 올라왔다 — 사용자가 자리를 바꿨다
/// > *"목록이 뜨는 건 좋은데 화면 가장 아래에서 올라오는 방식이야. 나는 같은 방식의 목록이,
/// > 내가 누른 네모 바로 아래에 붙어서 내려오는 형식의 목록이면 좋겠어."*
///
/// **목록의 꼴은 그대로 두고 자리만 바꿨다** — 시트에서 **팝오버**로.
/// ⚠️ **아이폰에서는 팝오버가 저절로 시트로 바뀐다** — `presentationCompactAdaptation(.popover)`가 그것을 막는다
/// (iOS 16.4부터 · 이 앱은 26.0이다). ★ **이 앱의 첫 팝오버 자리다** —
/// 다음에 또 팝오버를 쓸 때 **여기와 같은 꼴로** 한다(첫 자리가 규칙이 되는 꼴 · `DetailView`의 「동작 줄이기」와 같은 결).
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
    let urls: [URLEntry]
    /// 고른 URL — ⚠️ **팝오버를 먼저 닫고** 브라우저를 연다(겹쳐 띄우면 iOS가 둘째를 무시한다).
    var onPick: (URLEntry) -> Void
    /// **빨간 X** — 그 URL을 자료에서 뗀다(2026-08-25 사용자 요청 · §3-Z-10).
    /// ⚠️ **여기서 지우지 않는다** — 팝오버를 닫고 **상세가 확인을 묻는다**(정본: 되돌리기 없음).
    var onDelete: (URLEntry) -> Void

    /// ★ **줄 하나 56pt · 최대 다섯 줄까지 자라고 그보다 많으면 안에서 스크롤한다**(2026-08-25).
    ///
    /// ⛔ **처음엔 경계가 없었다** — 사용자가 물어서 드러났다(*"목록이 길어지면 어떤 일이 생기는지 궁금"*).
    /// 스크롤이 없으면 줄이 늘수록 팝오버가 계속 길어지고, 화면을 넘으면 **아래 줄에 닿을 방법이 없어진다.**
    /// 게다가 팝오버는 **아래 공간이 부족하면 위로 뒤집혀** 떠서 「네모 아래」도 아니게 된다.
    /// **다섯 줄 = 296pt**라 화면 어디에 붙어도 안전하다.
    private static let rowHeight: CGFloat = 56
    private static let maxRows = 5

    private var maxHeight: CGFloat { CGFloat(Self.maxRows) * Self.rowHeight }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(urls.enumerated()), id: \.offset) { i, e in
                    row(e)
                    if i != urls.count - 1 { Divider().padding(.leading, 56) }
                }
            }
        }
        // 줄이 적으면 그만큼만 — 많으면 다섯 줄에서 멈추고 스크롤한다
        .frame(height: min(CGFloat(urls.count) * Self.rowHeight, maxHeight))
        .scrollBounceBehavior(.basedOnSize)
        .padding(.vertical, 8)
        // ⚠️ **팝오버는 내용 크기로 잡힌다** — 줄이 `Spacer()`로 늘어나므로 폭을 정해 준다.
        //    280pt = 화면 폭 402에서 좌우가 남아 **어느 네모에 붙어도 화면을 안 넘는다**.
        .frame(width: 280)
        .presentationCompactAdaptation(.popover)   // ⛔ 없으면 아이폰에서 다시 시트가 된다
    }

    /// 줄 하나 — **누르는 자리가 둘이다.** 줄 몸통은 「열기」, 오른쪽 끝 X는 「뗀다」.
    /// ⚠️ **X를 줄 버튼 안에 넣으면 안 된다** — 그러면 X를 눌러도 줄이 눌린다. 그래서 **나란히** 둔다.
    @ViewBuilder private func row(_ e: URLEntry) -> some View {
        HStack(spacing: 0) {
            Button { onPick(e) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "link")
                        .font(.system(size: 18))
                        .frame(width: 26)
                        .foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        // 짧은 이름을 굵게 — 네모에 보이는 것과 **같은 말**이라 눈이 잇는다
                        if let s = URLAsset.shortName(e.value) {
                            Text(s).font(.body).foregroundStyle(Palette.textPrimary)
                        }
                        // 그 아래 URL 전체를 한 줄로 — 둘을 가르는 것은 대개 뒷부분이다
                        Text(e.value).font(.caption).foregroundStyle(Palette.textSecondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.leading, 20)
                .frame(height: Self.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // **빨간 X** — 색은 이 앱이 「지움」에 쓰는 색 그대로다(`Palette.overdue`).
            Button { onDelete(e) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.overdue)
                    .frame(width: 44, height: Self.rowHeight)   // 권장 표적 44pt
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// 줄 하나가 가리키는 것 — **값만으로는 부족하다.**
/// ⛔ **같은 URL을 두 번 붙일 수 있어서** 「어느 것을 지우나」는 **자료 id**로만 정해진다.
/// (`assetId == nil`은 옛 단일 필드인데 URL에는 그런 것이 없다 — 그래도 꼴을 맞춰 둔다.)
struct URLEntry: Identifiable {
    let assetId: String?
    let value: String
    var id: String { assetId ?? "-\(value)" }
}

/// `popover(item:)`에 넘기려면 `Identifiable`이 필요하다.
struct URLPick: Identifiable {
    let urls: [URLEntry]
    var id: String { urls.map(\.id).joined(separator: "|") }
}
#endif
