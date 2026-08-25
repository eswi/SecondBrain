#if os(iOS)
import SwiftUI
import SecondBrainCore

/// **「URL 담기」** — 카드의 `+` → 종류 시트에서 「URL」을 누르면 뜬다.
///
/// ## ★ 화면에 나오는 말은 사용자가 정했다 (2026-08-24 · 항시 규칙 6)
/// - 화면 제목 = **「URL 담기」**
/// - 칸이 비었을 때 안내 = **`https://…`**
/// - URL처럼 안 보일 때 = **「URL이 아닌 것 같아요」 한 줄 + 저장을 말린다**
/// - 버튼 = **「저장」·「취소」** — ⛔ **앱에 이미 있는 말이라 새로 짓지 않았다.**
///
/// ## 클립보드를 미리 채운다 (사용자 결정 · 설계 §3-Z-2 B)
/// **붙이는 것은 거의 언제나 다른 앱에서 복사해 온 것**이라, 클립보드에 URL이 있으면 **미리 넣어 둔다.**
/// ⚠️ **읽기만 한다** — 클립보드를 비우거나 바꾸지 않는다.
///
/// ### ⛔ **iOS가 「붙여넣기 허용?」을 묻는다 — 실기기에서 확인했다** (2026-08-24 사용자 판정)
/// **옛 서술(틀렸다 · 지우지 않고 남긴다):** *"`hasURLs`로 먼저 걸러 본 뒤 읽는다"* 라고 적으면서
/// **그렇게 하면 팝업을 피한다는 뜻으로 적었다.** ⛔ **폰에서는 팝업이 떴다** —
/// 사용자: *"자동으로 채워지기 전에 복사를 허용할 것인지 묻는 iOS 팝업이 먼저 떠서 허용했더니 자동으로 들어옴."*
/// ✅ **한 번 허용하면 다른 기억에서도 채워진다**(같은 판정에서 확인됐다).
///
/// ### ⛔⛔ **그리고 `hasURLs`가 실제로 막고 있었다 — 같은 줄이 두 번 틀렸다** (2026-08-25 사용자 발견)
/// 사용자: *"클립보드에 지금 URL이 하나 들어있는데 … 왜 자동으로 URL이 입력되지 않을까?"*
/// (`https://www.inven.co.kr/board/wow/1896/51277`)
///
/// **★ 원인이 갈렸다 — 판정은 통과했다.** `URLAsset.isLikelyURL`에 넣어 **쟀고 `true`였다.**
/// **그러니 막은 것은 클립보드 검사다.**
/// ⛔ **`hasURLs`는 「URL 자료형(`public.url`)으로 들어 있을 때」만 참이다.**
/// 사파리 주소창에서 복사하면 그 자료형이 붙지만, **웹페이지 본문·채팅·메모에서 글자로 복사하면
/// 「평문」으로 들어가서 주소인데도 거짓**이다.
///
/// **✅ 고친 방법:** **`hasStrings`로 걸러 읽고 `URLAsset.isLikelyURL`로 판정한다**(아래 `fillFromClipboard`).
/// ⚠️ **옛 서술이 두 번째로 뒤집혔다:** *"`hasURLs`를 그대로 두는 이유는 … 클립보드에 URL이 없으면
/// 아예 안 읽는 것이다"* — **그 줄은 「URL이 있는데도 안 읽는」 쪽으로 작동하고 있었다.**
/// ★ **같은 한 줄을 두 번 틀렸다** — 처음엔 **왜 두는지**를, 두 번째는 **무엇을 하는지**를 틀렸다.
struct URLAddSheet: View {
    /// 저장을 누르면 **다듬은 값**이 온다(`URLAsset.normalized` — 스킴이 없으면 `https://`가 붙는다).
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var focused: Bool

    /// 「URL이 아닌 것 같아요」를 띄우나 — **빈 칸에서는 안 띄운다**(아무것도 안 한 사람을 나무라지 않는다).
    private var looksWrong: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !URLAsset.isLikelyURL(text)
    }

    private var canSave: Bool { URLAsset.isLikelyURL(text) }

    /// 클립보드에 주소가 있으면 미리 넣는다.
    ///
    /// ⛔ **`hasURLs`만으로는 안 된다 — 평문으로 복사된 주소를 놓친다**(2026-08-25에 실제로 놓쳤다).
    /// **`hasStrings`로 바꿨다:** 클립보드에 **글자가 있으면 읽고**, 읽은 값을 **`URLAsset.isLikelyURL`로
    /// 판정해서** 주소일 때만 넣는다.
    ///
    /// ⚠️ **안 고른 길:** `detectPatterns(for: [.probableWebURL])`(iOS 14+) — **평문 속 주소만 골라내므로
    /// 더 좁게 읽을 수 있다.** ⛔ **그런데 그 Swift 이름을 못 찾았다**(`UIPasteboard.DetectionPattern`이
    /// 안 나온다 · 헤더에는 `NS_REFINED_FOR_SWIFT`로 되어 있다). **짐작으로 두 번 시도해 둘 다 안 되어 물렀다.**
    /// **다시 시도할 값은 있다** — 그때는 Swift 쪽 이름을 먼저 확인한다.
    ///
    /// **대가:** 클립보드에 **주소가 아닌 글자**가 있어도 한 번 읽는다(그리고 판정에서 버린다).
    /// ⚠️ 그러면 **「붙여넣기 허용?」 물음이 더 자주 뜰 수 있다.**
    /// ★ **그래도 이쪽을 골랐다** — 이 화면은 **주소를 붙이려고 여는 화면**이라 클립보드를 보는 것이
    /// 사용자의 뜻과 어긋나지 않고, ⛔ **주소가 있는데 안 채워지는 것이 훨씬 나쁘다**(그것이 이번 결함이다).
    private func fillFromClipboard() async {
        guard text.isEmpty else { return }
        let pb = UIPasteboard.general
        guard pb.hasStrings || pb.hasURLs else { return }
        guard let s = pb.string, URLAsset.isLikelyURL(s) else { return }
        text = s
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                TextField("https://…", text: $text, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .lineLimit(1...4)
                    .font(.body)
                    .focused($focused)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface2))

                // 앱의 기존 방식 — 한 줄 도와준다(「본문은 비울 수 없어요」와 같은 자리).
                if looksWrong {
                    Text("URL이 아닌 것 같아요")
                        .font(.caption)
                        .foregroundStyle(Palette.overdue)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("URL 담기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.tint(Palette.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        if let v = URLAsset.normalized(text) { onSave(v) }
                        dismiss()
                    }
                    .disabled(!canSave)          // ⛔ 사용자 결정 — 아니면 저장을 말린다
                    .tint(Palette.accent)
                }
            }
            .task {
                await fillFromClipboard()
                focused = true
            }
        }
    }
}
#endif
