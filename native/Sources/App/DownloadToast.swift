import SwiftUI

/// **「내려받는 중」 토스트** — 받아오는 동안만 뜬다.
///
/// ## ★ 여기 모여 있는 이유 — **복제가 늘지 않게** (2026-08-26)
/// 2026-08-26 새벽에 이 꼴을 **뷰어 안에 만들면서** 그 자리에 이렇게 적어 뒀다:
/// *"⚠️ **복제다 — 한쪽을 고치면 다른 쪽은 안 따라온다.**"*
/// 같은 날 낮에 **상세에도 같은 표시가 필요해졌다**(「미리보기 다시 받기」) —
/// ⛔ 그때 또 복제하면 **셋이 된다.** 그래서 **한 자리로 모았다.**
/// ★ **경고를 적어 뒀더니 두 번째에 걸렸다** — 08-25의 *"예고를 적어 두면 맞는다"*와 같은 형태다.
///
/// ## ★★ 문구는 새로 지은 것이 아니다 — **앱에 이미 있는 말이다**
/// **「내려받는 중」** = 설정 ▸ 「연결된 폴더」가 받는 중일 때 쓰는 말
/// (`SettingsView.folderStatusLabel` · 문구 확정 2026-08-06). 항시 규칙 6의 거꾸로 쓰기.
///
/// ## ⛔ 있는 토스트를 안 쓴 이유 — **자동 분류 것이다**
/// `InboxModel.autoToast`·`ClassifyToastView`는 **자동 분류 전용**이고, 자동 분류는
/// **zero base로 새로 설계**하기로 정해져 있다(항시 규칙 8 — 허락 없이는 한 줄도).
/// **꼴만 따랐다** — 둥근 네모 20 · `surface2` · 테두리 · 그림자 · 빙글빙글 + 글자.
/// ⚠️ **그쪽과는 아직 복제 관계다** — 합치려면 자동 분류 영역을 건드려야 하므로 **안 합쳤다.**
struct DownloadToast: View {

    /// 위에서 얼마나 내려앉나.
    /// ⚠️ **재서 정한 값이 아니다** — 뷰어에서는 위쪽 「n / n」을 비켜 앉히려고 준 값이다
    /// (계측 규칙 7 · 「짐작」으로 적어 둔다). 화면에서 겹쳐 보이면 부르는 쪽이 고친다.
    var topPadding: CGFloat = 56

    var body: some View {
        VStack {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(Palette.accent)
                Text("내려받는 중")
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(minWidth: 200)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.surface2)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Palette.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
            )
            .padding(.top, topPadding)
            Spacer()
        }
        // ⛔ **터치를 막지 않는다** — 있는 토스트와 같다. 밑에서 넘기기·닫기가 계속 눌린다.
        .allowsHitTesting(false)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}
