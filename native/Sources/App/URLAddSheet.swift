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
/// **`hasURLs`를 그대로 두는 이유는 팝업 회피가 아니다** — **클립보드에 URL이 없으면 아예 안 읽는 것**이다.
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
            .onAppear {
                // 클립보드에 URL이 있으면 미리 넣는다. **URL이 없으면 클립보드를 읽지도 않는다.**
                if text.isEmpty, UIPasteboard.general.hasURLs,
                   let s = UIPasteboard.general.string, URLAsset.isLikelyURL(s) {
                    text = s
                }
                focused = true
            }
        }
    }
}
#endif
