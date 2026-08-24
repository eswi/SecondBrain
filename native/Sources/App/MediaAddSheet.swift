#if os(iOS)
import SwiftUI

/// **자료를 붙일 때 종류를 먼저 고르는 시트** — 카드의 점선 `+`를 누르면 뜬다.
///
/// ## ★ 왜 종류를 먼저 고르나 (2026-08-23 사용자 결정)
/// > *"종류별로 수집하는 방법이 달라서 어차피 다른 방법의 도구로 들어가야 할 것이라,
/// > 그 분기를 `+` 기호를 누른 순간 하는 것이 맞다고 생각했거든."*
///
/// **사진만 두 줄로 갈라져 있다**(찍기 / 앨범) — 사용자 결정: *"두 방법을 이번에 구분한다면
/// 하나는 '앨범에서 고르기', 하나는 '사진 찍기'로 하자."* **「사진 찍기」는 수집 화면에 이미 있는 말이다.**
///
/// ## ⛔ 아직 안 되는 것을 **숨기지 않고 보인다** — 그리고 누르면 알린다
/// ⚠️ **개수를 안 적는다** — 종류가 열릴 때마다 낡는다(2026-08-24에 다섯 → 넷이 됐다 · 기록 규칙 8).
/// **옛 원칙이 뒤집혔다**(2026-08-23 사용자): `MediaCard`의 추가 네모 주석은
/// *"누르면 아무 일 없는 단추를 만들지 않고, 없는 기능을 알리는 문구도 짓지 않는다"* 였다.
/// **지금은 종류를 다 보이고, 안 되는 것을 누르면 「아직 못 담아요」를 그 줄에 띄운다.**
/// ⚠️ **시트는 안 닫힌다** — 그 자리에서 바로 다른 종류를 눌러 볼 수 있게(사용자 결정).
struct MediaAddSheet: View {
    var onCamera: () -> Void
    var onAlbum: () -> Void
    /// ✅ **2026-08-24부터 URL이 눌린다** — 「URL 담기」로 간다(설계 §3-Z).
    var onURL: () -> Void = {}

    /// 「아직 못 담아요」를 보이고 있는 줄. 다른 줄을 누르면 그 줄로 옮겨간다.
    @State private var notYet: String?

    /// 아직 못 담는 넷 — **이름은 사용자가 쓴 말 그대로**(§3-C-2의 종류 여섯과 짝).
    ///
    /// ⚠️ **「URL」이 여기서 빠졌다**(2026-08-24) — 이제 담을 수 있다.
    /// ⛔ **「동영상」은 못 담는 것이 아니라 미룬 것이다** — 용량 때문에 **자료 종류 중 맨 뒤**로
    /// 밀렸다(사용자 결정 · `CLAUDE.md` 「미뤄둔 것」). **화면에서는 둘이 똑같이 보인다** —
    /// 「아직 못 담아요」 하나로 덮인다(문구를 가를지는 사용자에게 안 물었다).
    private static let notYetRows: [(name: String, icon: String)] = [
        ("동영상", "video.fill"),
        ("음성", "waveform"),
        ("PDF", "doc.richtext"),
        ("기타", "doc"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            row("사진 찍기", icon: "camera.fill", action: onCamera)
            divider
            row("앨범에서 고르기", icon: "photo.on.rectangle", action: onAlbum)
            divider
            row("URL", icon: "link", action: onURL)
            divider
            ForEach(Self.notYetRows, id: \.name) { r in
                row(r.name, icon: r.icon, disabled: true) { notYet = r.name }
                if r.name != Self.notYetRows.last?.name { divider }
            }
        }
        .padding(.top, 8)
        // ⚠️ 되는 줄이 **셋**(사진 찍기 · 앨범에서 고르기 · URL) + 못 담는 넷 = 일곱 줄이다.
        .presentationDetents([.height(CGFloat(Self.notYetRows.count + 3) * 56 + 40)])
    }

    private var divider: some View {
        Divider().padding(.leading, 56)
    }

    @ViewBuilder
    private func row(_ label: String, icon: String, disabled: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 26)
                    .foregroundStyle(disabled ? Palette.textTertiary : Palette.accent)
                Text(label)
                    .foregroundStyle(disabled ? Palette.textTertiary : Palette.textPrimary)
                Spacer()
                // 「아직 못 담아요」 — **시트 안에 한 줄로**(사용자 결정). 누른 줄에만 뜬다.
                if notYet == label {
                    Text("아직 못 담아요")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif

/// `+` 시트에서 고른 길 — **시트가 닫힌 뒤** 무엇을 열지 기억한다(겹쳐 띄우면 둘째가 무시된다).
enum MediaAddRoute {
    case camera
    case album
    case url
}
