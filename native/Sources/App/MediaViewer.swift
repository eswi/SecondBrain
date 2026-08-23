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
//  ── ✅ `‹` `›`가 들어왔다 (2026-08-24) ─────────────────────────
//  **같은 종류 안에서만 넘긴다**(§0 24번). 사진이 실제로 여럿이 된 뒤에야 필요해진 자리다
//  (3단계에서 한 항목에 둘·셋·다섯이 생겼다 — 설계 §3-Y-3).
//  **사용자 결정 둘(2026-08-24):** 자리 표시는 **숫자 「2 / 3」**(음성의 「경과 / 길이」와 **같은 꼴** —
//  새 문구를 안 짓는다) · 넘기는 것은 **단추만**(⛔ 스와이프는 확대 제스처와 싸운다).
//
//  ⏸ **여기 없는 것(뷰어 상세 문서로 간다):** 추가 · 삭제 · **위치 보기** ·
//     자료마다 개별 보기(수집 시각·기기) · **URL 뷰어**(QuickLook이 못 하던 그 자리) ·
//     **대표 사진 정하기**(§3-Y-8 — 「붙인 순서」를 알려면 필드별 HLC를 내보내야 한다).
//

struct MediaViewer: View {
    let item: ResolvedItem
    let kind: MediaCardKind
    @ObservedObject var audio: AudioPlayer
    var onClose: () -> Void

    /// 막대를 끌기 **직전에** 듣고 있었나 — 손을 떼고 이어 들을지 정한다.
    @State private var wasPlayingBeforeScrub = false
    /// 지금 보고 있는 것이 **이 종류의 몇 번째**인가.
    @State private var index = 0

    /// 이 종류의 자료 파일 이름들 — **포인터 값을 읽는다**(C 뒤 · `ResolvedItem.mediaNames`).
    /// ⚠️ 첫째는 **수집 당시의 원본**이다(성역을 먼저 읽는다 · §3-Y-8).
    private var names: [String] { item.mediaNames(kind) }

    /// 지금 것. 목록이 바뀌어 index가 넘치면 **첫째로 돌아간다**(삭제가 들어오면 그 자리다).
    private var name: String? {
        names.indices.contains(index) ? names[index] : names.first
    }
    // ⛔ **확대 상태(`zoom`·`pan`…)는 여기 없다** — `UIScrollView`가 들고 있다(`ZoomableImage`).
    //    옛 꼴이 그것을 SwiftUI `@State`로 들다가 **경계가 없어 사진이 화면 밖으로 나갔다.**

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            closeButton
            counter
            arrows
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
        // C 뒤 — **포인터 값으로 찾는다**(§3-X). `‹` `›`로 고른 것을 본다.
        if let url = name.flatMap({ PhotoStore.url(name: $0) }) {
            #if os(iOS)
            // ⛔ **손으로 만든 확대를 버리고 `UIScrollView`로 갔다** (2026-08-23 · 실기기 판정).
            //    셋이 함께 풀린다: **두드린 지점 중심** · **부드러운 확대/축소** · **경계 제한**.
            //    전말은 `ZoomableImage.swift` 머리주석 · 설계 §3-R.
            if let ui = UIImage(contentsOfFile: url.path) {
                // ⚠️ **`id`를 이름으로 준다** — 넘기면 확대 상태가 **새로 시작**한다
                //    (`UIScrollView`가 확대를 들고 있으므로, 같은 뷰를 재사용하면 앞 사진의 확대가 남는다).
                ZoomableImage(image: ui)
                    .id(url.lastPathComponent)
            } else {
                missing
            }
            #else
            // 맥은 전체 보기로 남는다(`UIViewRepresentable`은 iOS 전용).
            if let img = PlatformMedia.image(contentsOfFile: url.path) {
                img.resizable().scaledToFit()
            } else {
                missing
            }
            #endif
        } else {
            missing
        }
    }

    // MARK: 음성 — 아이콘 · 길이 · 재생/정지 · 진행 막대
    @ViewBuilder private var audioBody: some View {
        if let url = name.flatMap({ AudioStore.url(name: $0) }) {
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
                // ⛔ **끄는 동안은 소리를 멈춘다** (2026-08-23 사용자):
                //    *"slider를 움직이는 동안에는 소리가 안 나게 해줘. **듣기 싫은 소리가 남**."*
                //    끌기 시작하면 멈추고, 손을 떼면 **끌기 전에 듣고 있었을 때만** 이어 듣는다.
                Slider(value: Binding(get: { audio.progress },
                                      set: { audio.seek(toFraction: $0) }),
                       in: 0...1,
                       onEditingChanged: { editing in
                           if editing {
                               wasPlayingBeforeScrub = audio.isPlaying
                               if audio.isPlaying { audio.pause() }
                           } else if wasPlayingBeforeScrub {
                               audio.toggle(url: url)        // 멈춰 있던 자리에서 이어 듣는다
                           }
                       })
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

    /// **「2 / 3」** — 사용자 결정(2026-08-24). **음성의 「경과 / 길이」와 같은 꼴**이라 새 문구가 아니다.
    /// 하나뿐이면 **안 보인다**(셀 것이 없다).
    @ViewBuilder private var counter: some View {
        if names.count > 1 {
            VStack {
                Text("\(min(index, names.count - 1) + 1) / \(names.count)")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.45)))
                    .padding(.top, 10)
                Spacer()
            }
        }
    }

    /// `‹` `›` — **같은 종류 안에서만**(§0 24번). 좌우 가장자리 세로 중앙 · 닫기(X)와 같은 꼴.
    /// **끝에서는 흐려지고 안 눌린다** — 순환하지 않는다(사진 앱과 같은 결).
    /// ⛔ **스와이프는 안 넣는다**(사용자 결정) — 확대 제스처와 싸운다.
    @ViewBuilder private var arrows: some View {
        if names.count > 1 {
            HStack {
                arrow("chevron.left", enabled: index > 0) { step(-1) }
                Spacer()
                arrow("chevron.right", enabled: index < names.count - 1) { step(1) }
            }
            .padding(.horizontal, 8)
        }
    }

    private func arrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.25))
                .padding(14)
                .background(Circle().fill(.black.opacity(enabled ? 0.45 : 0.2)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// 넘긴다. ⚠️ **음성은 멈춘다** — 넘긴 뒤에도 앞 소리가 이어지면 어느 것을 듣는지 알 수 없다.
    private func step(_ delta: Int) {
        let next = index + delta
        guard names.indices.contains(next) else { return }
        if kind == .voice { audio.stop() }
        index = next
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
