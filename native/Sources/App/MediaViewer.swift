import SwiftUI
import SecondBrainCore

//
//  MediaViewer — **최소 뷰어** (2026-08-23 신설 · 자료 확장 ② 커밋 ②-1)
//
//  ── 무엇까지인가 (사용자 2026-08-23) ────────────────────────────
//  *"㉮ 최소 뷰어 — 한 장 · 확대/축소 · 닫기까지. `<` `>` · 추가 · 삭제는 나중."*
//  거기에 **음성 재생기**(아이콘 · 길이 · 재생/정지 · 진행 막대)가 들어간다.
//
//  ── 왜 음성도 여기서 여나 ──────────────────────────────────────
//  사용자 근거 셋(설계 §3-J-5 → 확정):
//  ① **입구가 하나로 유지된다** — 「네모를 누르면 뷰어」가 음성에서만 거짓이 되면
//     *"어떤 네모는 뷰어고 어떤 것은 재생인지 사용자가 외워야 한다."*
//  ② 상세에 다시 듣기를 남기면 **자료가 두 곳에 있어** 성역에서 뗀 결정이 반만 된다.
//  ③ *"「화면을 다 쓴다」는 뷰어 상세 설계 때 줄일 수 있다. 지금 구조를 정하는 근거가 못 된다."*
//
//  ⛔ **화면에 나오는 말이 없다** — 닫기는 아이콘, 길이는 숫자다.
//     **새 문구를 지어 넣지 않았다**(항시 규칙 6 — 문구는 사용자가 정한다).
//
//  ⏸ **여기 없는 것(뷰어 상세 문서로 간다):** `<` `>` · 추가 · 삭제 · **위치 보기** ·
//     자료마다 개별 보기(수집 시각·기기) · **URL 뷰어**(QuickLook이 못 하던 그 자리).
//

struct MediaViewer: View {
    let item: ResolvedItem
    let kind: MediaCardKind
    @ObservedObject var audio: AudioPlayer
    var onClose: () -> Void

    @State private var zoom: CGFloat = 1          // 확대 배율(1 = 전체 보기)
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            closeButton
        }
        #if os(iOS)
        .statusBarHidden(true)
        #endif
        .onDisappear { audio.stop() }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .photo: photoBody
        case .voice: audioBody
        default:
            // ⚠️ 지금 데이터로는 여기 올 일이 없다(포인터가 없다 · 설계 §3-J-1).
            Image(systemName: "doc").font(.system(size: 64)).foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: 사진 — **전체 보기**(안 자른다) + 확대/축소
    //
    // ★ **카드와 반대다** — 카드의 네모는 **자르고**(정사각형), 뷰어는 **안 자른다**(§0 23번).
    //   그래서 **썸네일과 실물이 다르게 보이는 것이 정상이다.**
    @ViewBuilder private var photoBody: some View {
        if let url = PhotoStore.url(forId: item.id),
           let img = PlatformMedia.image(contentsOfFile: url.path) {
            img.resizable().scaledToFit()
                .scaleEffect(zoom)
                .offset(pan)
                .gesture(
                    MagnificationGesture()
                        .onChanged { v in zoom = min(max(zoomBase * v, 1), 6) }
                        .onEnded { _ in
                            zoomBase = zoom
                            if zoom <= 1 { pan = .zero; panBase = .zero }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { v in
                            guard zoom > 1 else { return }
                            pan = CGSize(width: panBase.width + v.translation.width,
                                         height: panBase.height + v.translation.height)
                        }
                        .onEnded { _ in panBase = pan }
                )
                // 두 번 두드리면 전체 보기로 돌아온다 — **되돌릴 길이 없으면 확대가 함정이 된다.**
                .onTapGesture(count: 2) {
                    zoom = 1; zoomBase = 1; pan = .zero; panBase = .zero
                }
        } else {
            missing
        }
    }

    // MARK: 음성 — 아이콘 · 길이 · 재생/정지 · 진행 막대
    @ViewBuilder private var audioBody: some View {
        if let url = AudioStore.url(forId: item.id) {
            VStack(spacing: 28) {
                Image(systemName: "waveform")
                    .font(.system(size: 96, weight: .regular))
                    .foregroundStyle(Palette.accent)
                // ★ **경과 / 길이** — 옛 꼴은 길이만 보여서 **막대는 움직이는데 숫자가 안 변했다**
                //   (2026-08-23 실기기에서 사용자가 잡았다).
                Text("\(MediaViewer.clock(audio.currentTime)) / \(MediaViewer.clock(total(url)))")
                    .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                // ★ **끌어서 자리를 옮긴다** — `ProgressView`는 못 끈다. `Slider`라야 한다.
                Slider(value: Binding(get: { audio.progress },
                                      set: { audio.seek(toFraction: $0) }),
                       in: 0...1)
                    .tint(Palette.accent)
                    .frame(width: 260)
                // ★ **정지가 아니라 일시정지다** — 다시 누르면 **그 자리에서** 이어 듣는다.
                Button { audio.toggle(url: url) } label: {
                    Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }
        } else {
            missing
        }
    }

    /// 「0:37」 꼴. ⚠️ **카드의 길이 표시와 같은 꼴이어야 한다**(`MediaCard.durationText`).
    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// 총 길이 — 재생 전에는 `AudioPlayer`가 모르므로 파일에서 읽는다.
    private func total(_ url: URL) -> TimeInterval {
        audio.duration > 0 ? audio.duration : (MediaCard.durationSeconds(url) ?? 0)
    }

    /// 파일이 없을 때 — **카드가 이미 「아직 못 받음」으로 말한 상태**다. 여기서도 같은 뜻만 보인다.
    /// ⛔ **새 문구를 안 짓는다** — 뷰어가 할 말은 뷰어 상세 문서에서 정한다.
    private var missing: some View {
        Image(systemName: "icloud.and.arrow.down")
            .font(.system(size: 64)).foregroundStyle(.white.opacity(0.5))
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            Spacer()
        }
        .padding(16)
    }
}
