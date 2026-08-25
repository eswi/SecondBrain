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
    /// **썸네일 줄이 보이나** — 손을 뗀 지 잠깬 지나면 스스로 사라진다(2026-08-24 사용자).
    @State private var stripVisible = true
    /// 손이 닿을 때마다 늘어난다 — **이 값이 바뀌면 사라짐 시계가 처음부터 다시 간다.**
    @State private var touchTick = 0

    /// **손을 뗀 뒤 얼마나 있다 사라지나.** **5초**(2026-08-24 사용자 — 처음엔 *"3초쯤"*이었다).
    private static let stripHideAfter: Duration = .seconds(5)
    /// 사라짐·나타남은 **천천히** — 사용자: *"서서히 사라지게"*. ⚠️ 0.45는 재서 정한 값이 아니다.
    private static let fade = Animation.easeInOut(duration: 0.45)
    /// 썸네일 줄이 **따라 움직일 때** — 사진 전환보다 무르게.
    /// ⚠️ **두 번 고쳤다:** `0.38 / 0.9` → 사용자 *"좀 뻑뻑하고"*(2026-08-24) → **`0.55 / 0.82`**.
    /// **되돌림이 아니라 같은 방향으로 한 걸음 더 간 것이다**(팍팍 → 부드럽게 → 더 부드럽게).
    private static let stripScroll = Animation.spring(response: 0.55, dampingFraction: 0.82)

    /// 마지막으로 어느 쪽으로 넘겼나(`+1` 다음 · `-1` 이전) — **전환이 그 방향으로 미끄러진다.**
    @State private var lastStep = 1

    /// **전환 값** — ⚠️ 재서 정한 값이 아니다. 사용자 판정: *"너무 팍 팍 넘어가. 너무 기계적"*.
    /// 카드 이동은 0.35초인데(§0 30번) **사진 넘기기는 그보다 빨라야** 연달아 넘길 때 답답하지 않다.
    private static let slide = Animation.easeInOut(duration: 0.26)

    /// 이 종류의 자료 파일 이름들 — **포인터 값을 읽는다**(C 뒤 · `ResolvedItem.mediaValues`).
    /// ⚠️ 첫째는 **수집 당시의 원본**이다(성역을 먼저 읽는다 · §3-Y-8).
    private var names: [String] { item.mediaValues(kind) }

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
            filmstrip
        }
        // ★ **어떤 목적으로 손을 대든** 썸네일 줄이 다시 나타난다(사용자 문장).
        //   `minimumDistance: 0`이라 **누르는 순간** 걸리고, `simultaneousGesture`라
        //   ⛔ **확대·끌기·단추를 막지 않는다**(막으면 뷰어가 통째로 죽는다).
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in wake() })
        // 손이 닿을 때마다 이 작업이 취소되고 새로 시작한다 = **마지막 손댐부터 3초.**
        .task(id: touchTick) {
            // ⛔⛔ **`try?`로 삼키면 안 된다 — 2026-08-24에 여기가 결함이었다.**
            //    `Task.sleep`은 **취소되면 곧바로 던진다.** `try?`는 그것을 nil로 삼키고
            //    **다음 줄이 그대로 실행된다** → 손이 움직이는 동안 `touchTick`이 수십 번 바뀌며
            //    앞 작업이 취소될 때마다 **즉시 「사라져라」가 돌았다.**
            //    사용자 판정: *"자꾸 1초도 안 되어 사라지는 일이 생겨."*
            // ✅ **취소면 아무것도 하지 않는다** — 사라짐은 **끝까지 잔 작업만** 낸다.
            do { try await Task.sleep(for: Self.stripHideAfter) } catch { return }
            withAnimation(Self.fade) { stripVisible = false }
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
            // ⛔ **옛 서술이 틀렸다** — *"지금 데이터로는 여기 올 일이 없다(포인터가 없다 · 설계 §3-J-1)."*
            //   **URL 종류가 생겨서 이제 온다**(2026-08-25 · 설계 §3-Z-14). ⚠️ **맥에서만** 온다 —
            //   iOS는 URL 네모를 **앱 안 보기**로 보내므로(§3-Z-2 G) 뷰어에 안 들어온다.
            //   ⛔ **맥에는 앱 안 보기가 없어서** URL 네모가 뷰어로 오고 **이 회색 아이콘만 보인다.**
            //   ⏸ **맥에서 URL을 어떻게 열지는 안 정했다** — 사용자 결정 사안이다(§3-Z-14).
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
                ZoomableImage(image: ui) { step($0) }   // 끝까지 당기면 넘긴다
                    .id(url.lastPathComponent)
                    // ★ **미끄러져 들어오고 미끄러져 나간다** — 넘긴 방향으로.
                    //   `.id`가 바뀌면 뷰가 갈리는데, 그 갈림에 전환을 붙인 것이다.
                    .transition(.asymmetric(
                        insertion: .move(edge: lastStep > 0 ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: lastStep > 0 ? .leading : .trailing).combined(with: .opacity)))
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
    ///
    /// ⛔ **「하나뿐이면 안 보인다」가 뒤집혔다**(2026-08-24 사용자 판정):
    /// *"사진이 하나뿐일 경우 … `<` `>` 안 보이는데, **옳지않아.** 같은 색으로 흐리게 보이게 해줘.
    /// **1/1도 표시**해주고. **UI의 일관성**이야."*
    /// ★ 내 판단은 「셀 것이 없으면 감춘다」였고, 사용자 기준은 **「자리가 늘 같아야 한다」**였다.
    @ViewBuilder private var counter: some View {
        if !names.isEmpty {
            VStack {
                Text("\(min(index, names.count - 1) + 1) / \(names.count)")
                    .font(.body.weight(.semibold)).monospacedDigit()   // subheadline보다 2pt 크다(사용자 요구)
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
    /// **하나뿐이어도 흐리게 보인다** — 자리가 늘 같아야 한다(사용자 판정 · 위 `counter` 참고).
    ///
    /// ⛔ **「단추만」이 뒤집혔다**(2026-08-24) — **스와이프도 넣었다**(`ZoomableImage.onStep`).
    /// 옛 판단은 *"확대 제스처와 싸운다"*였는데, **끝까지 당겼을 때만** 넘기면 안 싸운다
    /// (사용자가 그 조건을 지정했다: *"이동이 다 되어 사진의 끝에 걸리면"*).
    ///
    /// ⛔ **2026-08-24 정정 — 내가 잘못 읽었다.** *"`<` `>` 기호는 아래에서는 쓰지말기"*를
    /// 「세로에서는 화살표를 안 그린다」로 읽었는데, 뜻은 **「썸네일 줄 안에 화살표를 넣지 말라」**였다.
    /// 사용자: *"원래 있던 `<` `>` 없어졌어 … **크기 2배로 키우라 했고 그걸로도 다음 사진, 이전 사진 고르기 할거거든.**"*
    /// → **세로·가로 둘 다 그린다.** 썸네일 줄은 화살표를 **대신하는 것이 아니라 곁들이는 것**이다.
    @ViewBuilder private var arrows: some View {
        if !names.isEmpty {
            HStack {
                arrow("chevron.left", enabled: index > 0) { step(-1) }
                Spacer()
                arrow("chevron.right", enabled: index < names.count - 1) { step(1) }
            }
            .padding(.horizontal, 8)
        }
    }

    /// **하단 썸네일 줄** — 사진에서만(⏸ **실험이었다 → 남긴다** · 2026-08-24 사용자: *"맘에 들어"*).
    /// ⛔ **「세로에서만」이 풀렸다**(같은 날) — *"아래 사진은 가로 모두에서도 동작하게 해줘."*
    /// 고른 것에 **초록 테두리** · 터치로 고른다 · 많아지면 좌우로 스크롤된다.
    /// ⚠️ 스크롤은 **이 줄 안에서만** 먹는다 — 사진 영역의 스와이프(넘기기)와 자리가 갈려 안 싸운다.
    @ViewBuilder private var filmstrip: some View {
        if kind == .photo, !names.isEmpty {
            VStack {
                Spacer()
                // ★ **고른 것이 화면 밖으로 나가지 않게 따라 스크롤한다**(2026-08-24 사용자):
                //   *"사진을 계속 넘겨서 … 결국 초록 테두리는 화면 밖으로 나가버려."*
                //   `ScrollViewReader`가 그 일을 한다 — **가운데로 모은다**(anchor: .center)라
                //   앞뒤가 함께 보여 「어디쯤인가」가 읽힌다.
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(names.enumerated()), id: \.element) { i, n in
                                    Button { pick(i) } label: { thumb(n, selected: i == index) }
                                        .buttonStyle(.plain)
                                        .id(n)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            // ★ **넘치지 않으면 가운데로 모인다**(2026-08-24 사용자: *"왼편에 붙어서 보여"*).
                            //   줄을 **최소 화면 폭**으로 넓히면 남는 자리가 양쪽으로 갈린다.
                            //   넘치면 이 최소값이 무의미해져 **그대로 스크롤된다.**
                            .frame(minWidth: geo.size.width, alignment: .center)
                        }
                        .background(.black.opacity(0.55))
                        // 넘길 때마다 · 그리고 열 때 한 번(대표가 첫째가 아닐 수도 있는 자리를 위해).
                        .onChange(of: index) { _, _ in scrollToCurrent(proxy) }
                        .onAppear { scrollToCurrent(proxy) }
                    }
                }
                .frame(height: Self.thumbSide + 16)
                // **서서히 사라지고 서서히 돌아온다** · 안 보일 때는 **터치를 안 받는다** —
                // ⛔ 안 그러면 안 보이는 줄이 첫 손댐을 먹어 「사진을 눌렀는데 썸네일이 골라진다」가 된다.
                .opacity(stripVisible ? 1 : 0)
                .allowsHitTesting(stripVisible)
            }
        }
    }

    private static let thumbSide: CGFloat = 56

    @ViewBuilder private func thumb(_ name: String, selected: Bool) -> some View {
        let img = PhotoStore.url(name: name).flatMap { MediaCard.thumbnail($0, side: Self.thumbSide) }
        ZStack {
            if let img {
                img.resizable().scaledToFill()
            } else {
                // 파일이 없거나 그림을 못 만든 것 — 카드와 같은 뜻만 보인다(새 문구를 안 짓는다).
                Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: Self.thumbSide, height: Self.thumbSide)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Palette.selected : .white.opacity(0.15),
                              lineWidth: selected ? 2.5 : 1)
        )
    }

    /// 손이 닿았다 — 줄을 되살리고 시계를 되돌린다.
    private func wake() {
        if !stripVisible { withAnimation(Self.fade) { stripVisible = true } }
        touchTick += 1
    }

    /// 지금 것을 **가운데로** 끌어온다. 목록이 짧아 스크롤할 여지가 없으면 아무 일도 안 난다.
    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard let n = name else { return }
        withAnimation(Self.stripScroll) { proxy.scrollTo(n, anchor: .center) }
    }

    private func pick(_ i: Int) {
        guard names.indices.contains(i), i != index else { return }
        if kind == .voice { audio.stop() }
        lastStep = i > index ? 1 : -1
        withAnimation(Self.slide) { index = i }
    }

    private func arrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .semibold))   // title3(20pt)의 2배 — 사용자 요구
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
        lastStep = delta
        withAnimation(Self.slide) { index = next }
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
