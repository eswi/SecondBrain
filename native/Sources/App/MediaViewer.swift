import SwiftUI
import CoreLocation
import ImageIO
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
//  ── ✅ **위치 보기**가 들어왔다 (2026-09-30 · 설계 §0 26번 · §3-Z-17) ─────────
//  사용자: *"'주차위치'를 기억하면 사진을 찍게 되는데 사진에 위치 정보가 있고 표시도 하는데도 위치를 보여줄 방법이
//  없어. … 사진을 선택하여 '사진 뷰어'로 진입하면 그 화면의 적절한 곳에 위치정보 조회 버턴이 나타나게 하고,
//  그 버튼을 누르면 지도가 표시되는 등의 방법으로 위치를 보여줘."*
//  · **우상단 핀 단추**(닫기와 같은 꼴 · 좌상단 닫기·가운데 「n / n」과 안 겹치는 빈자리) → 누르면 **지도 판**
//    (`PhotoPlaceMap` · 손으로 옮기고 키울 수 있다 · 「지도 앱에서 열기」) · 다시 누르거나 장을 넘기면 닫힌다.
//  · **위치 없는 장은 핀이 회색이고 눌리지 않는다** — §3-5 *"위치 없는 사진도 아이콘을 보여준다 — 회색으로"*의
//    앞 반. ⏸ **뒤 반(「누르면 위치 정보가 없다고 알린다」)은 문구가 필요해서 안 했다** — 사용자가 정한다(항시 규칙 6).
//  · **썸네일 줄의 장마다 우하단 핀** — 카드 네모(§0 18번)와 같은 그림, 같은 자리. 어느 장에 위치가 있나를 여기서 갈라 보인다.
//  · ⛔ **화면에 나오는 새 말은 없다** — 핀은 아이콘, 지도 판의 말은 이미 있던 「지도 앱에서 열기」·「촬영 위치」.
//
//  ⏸ **여기 없는 것(뷰어 상세 문서로 간다):** 추가 · 삭제 · ~~**위치 보기**~~(✅ 2026-09-30) ·
//     자료마다 개별 보기(수집 시각·기기) · **URL 뷰어**(QuickLook이 못 하던 그 자리) ·
//     **대표 사진 정하기**(§3-Y-8 — 「붙인 순서」를 알려면 필드별 HLC를 내보내야 한다).
//

struct MediaViewer: View {
    /// **무엇을 보나** (2026-09-03에 갈랐다).
    ///
    /// ⛔ **옛 꼴: `let item: ResolvedItem`** — 저장된 기억만 볼 수 있었고, 그래서
    /// **수집 화면은 이 뷰어를 못 썼다**(옛 주석: *"`MediaViewer`를 못 쓴다 —
    /// 저장된 항목의 포인터를 읽는다"*). 거기엔 **첫 장만 크게 보는 맨몸 화면**이 따로 있었다.
    /// ★ **사용자가 두 화면을 같은 방식으로 정했다**(*"수집화면에도 뷰어가 있어야겠네. 그렇게 만들자"*) —
    /// 그래서 **읽는 자리 하나만 갈랐다.** ⚠️ `item`이 쓰이던 곳은 **`names` 한 줄뿐이었다.**
    enum Source {
        /// 저장된 기억 — 포인터 값(파일명)을 읽는다.
        case saved(ResolvedItem)
        /// **아직 저장 전** — 임시 파일 그대로다(포인터도 자료 id도 없다).
        case draft([URL])
    }
    let source: Source
    let kind: MediaCardKind
    @ObservedObject var audio: AudioPlayer
    var onClose: () -> Void
    /// **썸네일의 빨간 X를 눌렀다** — 몇 번째인가. **nil이면 X를 안 그린다.**
    /// ⚠️ **묻는 것은 뷰어가 하고, 지우는 것은 부르는 쪽이 한다** — 저장 전(임시 파일)과
    /// 저장 후(포인터+사본)가 **지우는 방법이 다르기 때문**이다. **문구는 한 자리에 둔다.**
    var onDelete: ((Int) -> Void)? = nil

    /// 막대를 끌기 **직전에** 듣고 있었나 — 손을 떼고 이어 들을지 정한다.
    @State private var wasPlayingBeforeScrub = false
    /// 지금 보고 있는 것이 **이 종류의 몇 번째**인가.
    @State private var index = 0
    /// **썸네일 줄이 보이나** — 손을 뗀 지 잠깬 지나면 스스로 사라진다(2026-08-24 사용자).
    @State private var stripVisible = true
    /// 손이 닿을 때마다 늘어난다 — **이 값이 바뀌면 사라짐 시계가 처음부터 다시 간다.**
    @State private var touchTick = 0
    /// **지우려고 묻는 중인 자리** — nil이면 안 묻는 중(`model.pendingDelete`와 같은 성격).
    @State private var deleting: Int?
    /// **지도 판이 열려 있나** — 장을 넘기면 닫는다(다른 장의 위치를 보여주면 안 되므로 `index` 변화에 접는다).
    @State private var showPlace = false
    /// 뷰어가 차지하는 크기 — `‹` `›`를 어디까지 올릴지 계산하는 데 쓴다(§3-Z-17-4).
    @State private var viewSize: CGSize = .zero
    /// 지금 장의 **세로/가로 비율**(픽셀 · 방향 보정) — 사진이 화면에서 실제로 차지하는 세로를 알기 위해.
    @State private var imageAspect: CGFloat?
    /// **지도 판의 실제 높이**(카드 전체 · 잰 값). 2026-10-07 19:2x 사용자: *"가로 사진은 아랫부분이 약간 지도에 겹치네."*
    /// — 어림값 `placePanelHeight`가 **지도 260만 세고** 그 아래 「지도 앱에서 열기」 줄(+틈 6)을 빠뜨렸다(~23pt). 그래서 잰다.
    @State private var measuredPanelHeight: CGFloat = 0

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

    /// **지금 보는 그 장을 받아온다** (2026-08-26 사용자 결정).
    ///
    /// ## ★ 왜 뷰어에 생겼나 — **앰버의 약속이 안 지켜지고 있었다**
    /// 카드는 **첫째만** 받는다(`MediaCard`의 `start`). 그래서 **둘째부터는 아무도 안 받아줬고**,
    /// 뷰어에서 넘기면 **구름 아이콘만 영영** 보였다(2026-08-26 맥에서 사용자가 봤다 · 표본 `BFE53B0B`).
    /// ⛔ **앰버는 「기다리거나 눌러서 볼 수 있다」는 약속인데** 뒤엣것은 기다려도 안 오고 눌러도 안 왔다.
    ///
    /// **왜 여기인가:** 상세를 열 때 전부 받으면 「실체는 클라우드」가 무너진다
    /// (`MediaFetch` 머리주석: *"131개 … 다 받으면 무너진다"*). **넘어간 그 장만** 받는 것이
    /// 그 방침을 안 깨뜨리는 자리다.
    @StateObject private var fetch = MediaFetch()

    /// **전환 값** — ⚠️ 재서 정한 값이 아니다. 사용자 판정: *"너무 팍 팍 넘어가. 너무 기계적"*.
    /// 카드 이동은 0.35초인데(§0 30번) **사진 넘기기는 그보다 빨라야** 연달아 넘길 때 답답하지 않다.
    private static let slide = Animation.easeInOut(duration: 0.26)

    /// 이 종류의 자료 파일 이름들 — **포인터 값을 읽는다**(C 뒤 · `ResolvedItem.mediaValues`).
    /// ⚠️ 첫째는 **수집 당시의 원본**이다(성역을 먼저 읽는다 · §3-Y-8).
    private var names: [String] {
        switch source {
        case .saved(let it): return it.mediaValues(kind)
        // ⚠️ **파일명을 id로 쓴다** — 임시 파일 이름은 `sb-photo-<uuid>.jpg`라 서로 안 겹친다.
        case .draft(let urls): return urls.map(\.lastPathComponent)
        }
    }

    /// **그 이름의 파일 자리** — 저장된 것은 포인터 값으로 찾고, 저장 전은 **손에 든 임시 파일**이다.
    private func photoURL(_ name: String) -> URL? {
        switch source {
        case .saved: return PhotoStore.url(name: name)
        case .draft(let urls): return urls.first { $0.lastPathComponent == name }
        }
    }

    /// 받아올 수 있는 종류인가 — **파일이 있는 둘만**이다.
    /// ⛔ **URL은 nil이다** — 파일이 없으므로 받을 것이 없다(설계 §3-Z-2 A).
    /// 이 장의 EXIF 좌표 — 저장된 것은 이름으로(`PhotoStore`가 기억해 둔다) · 임시 파일은 경로로.
    private func coordinate(_ name: String) -> CLLocationCoordinate2D? {
        switch source {
        case .saved: return PhotoStore.coordinate(name: name)
        case .draft: return photoURL(name).flatMap { PhotoStore.coordinate(fileURL: $0) }
        }
    }

    private var fetchKind: MediaKind? {
        // ⛔ **저장 전에는 받아올 것이 없다** — 파일이 이미 손에 있다(클라우드에 올라간 적이 없다).
        if case .draft = source { return nil }
        switch kind {
        case .voice: return .audio
        case .photo: return .photo
        default:     return nil
        }
    }

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
                .offset(y: photoLift)                       // 지도 판이 열리면 사진을 밀어 올린다(`photoLift`)
                .animation(Self.fade, value: photoLift)     // 열고 닫을 때 · 판을 둔 채 장이 바뀌어 양이 달라질 때
            closeButton
            counter
            arrows
            filmstrip
            placePanel
            placeButton
            downloadToast
            // ★ **지우기 확인** — 문구는 사용자가 골랐다(2026-09-03 · 항시 규칙 6):
            //   **「사진을 지울까요? / 되돌릴 수 없어요. / 원본은 그대로 있어요.」** · 버튼 **「지우기」**.
            //   ⚠️ **마지막 줄이 정본이 요구한 말이다**(`edit-policy.md` ③ —
            //   *"확인 문구에 「원본은 지워지지 않는다」를 넣는다"*). **URL에는 안 넣었다** —
            //   거기는 사본이 없어 그 말이 당연한 말이 되기 때문이다(설계 §3-Z-10-4).
            //   ⛔ **버튼은 「삭제」가 아니라 「지우기」다** — 앱의 「삭제」는 **항목을 버리는 것**이고
            //   「지우기」는 **한 칸의 값을 없애는 것**이다. **이것이 바로 그 일이다.**
            if let i = deleting {
                ConfirmDialog(title: "사진을 지울까요?\n되돌릴 수 없어요.\n원본은 그대로 있어요.",
                              confirmTitle: "지우기", confirmTint: Palette.overdue,
                              onCancel: { deleting = nil },
                              onConfirm: {
                                  deleting = nil
                                  // ⚠️ **자리를 먼저 당겨 둔다** — 마지막 장을 지우면 목록이 짧아진다.
                                  //    `name`이 이미 「넘치면 첫째로」를 하지만, index를 그대로 두면
                                  //    **지운 자리의 다음 장이 아니라 첫 장으로 튄다.**
                                  if i <= index, index > 0 { index -= 1 }
                                  onDelete?(i)
                              })
            }
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
        // ★ **넘길 때마다 그 장을 받는다** — `id`가 이름이라 **넘기면 앞 작업이 취소되고 새로 시작한다.**
        //   ⚠️ 이미 있으면 `start`가 아무 일도 안 한다(그 함수의 첫 갈래) — **폰에서는 비용이 0이다.**
        .task(id: name) {
            guard let n = name, let mk = fetchKind else { return }
            fetch.start(mk, name: n)
        }
        // 토스트가 **떠오르고 스러진다** — 있는 토스트와 같은 값(`RootView`).
        .animation(.spring(duration: 0.3), value: fetch.state)
        .animation(.spring(duration: 0.3), value: fetch.timedOut)
        .onDisappear { audio.stop() }
        // ★ 장을 넘겨도 **새 장에 위치가 있으면 지도 판을 둔다**(새 좌표로 옮겨 간다) · 없으면 접는다
        //   (2026-10-07 19:2x 사용자: *"그 사진에 위치 정보가 있다면 지도 판을 없애지 말자. 만일 위치 정보가 없다면 그 때는 지금처럼"*).
        //   *(옛 · `a3dd79e`~`6299881`: 넘기면 무조건 접었다 — "다른 장의 지도를 들고 있지 않게")*
        .onChange(of: index) { _, _ in
            if currentCoordinate == nil { withAnimation(Self.fade) { showPlace = false } }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        .task(id: name) {
            imageAspect = (kind == .photo ? name.flatMap { photoURL($0) } : nil).flatMap { Self.aspect(of: $0) }
        }
    }

    // MARK: 위치 보기 (2026-09-30 · 머리주석)

    /// 지금 장의 좌표 — 사진일 때만.
    private var currentCoordinate: CLLocationCoordinate2D? {
        guard kind == .photo, let n = name else { return nil }
        return coordinate(n)
    }

    /// **우상단 핀 단추.** 위치가 있으면 흰색·눌린다, 없으면 회색·안 눌린다(§3-5의 「회색」).
    @ViewBuilder private var placeButton: some View {
        if kind == .photo, !names.isEmpty {
            let has = currentCoordinate != nil
            VStack {
                HStack {
                    Spacer()
                    Button { withAnimation(Self.fade) { showPlace.toggle() } } label: {
                        Image(systemName: showPlace ? "mappin.slash" : "mappin.and.ellipse")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(has ? .white : .white.opacity(0.3))
                            .padding(12)
                            .background(Circle().fill(.black.opacity(has ? 0.45 : 0.2)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!has)
                }
                Spacer()
            }
            .padding(16)
        }
    }

    /// **지도 판** — 화면 아래쪽, 썸네일 줄 바로 위. 배경을 눌러도 닫히지 않는다(지도를 손으로 움직이므로).
    @ViewBuilder private var placePanel: some View {
        if showPlace, let c = currentCoordinate {
            VStack {
                Spacer()
                PhotoPlaceMap(coord: c, height: 260, interactive: true)
                    .id(name)                                   // 장이 바뀌면 지도를 새 좌표로 다시 놓는다(`initialPosition`은 안 따라간다)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.75)))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredPanelHeight = $0 }
                    .padding(.horizontal, 12)
                    .padding(.bottom, Self.placePanelBottom)     // 썸네일 줄 높이 + 틈
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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
        if let url = name.flatMap({ photoURL($0) }) {
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
                // ⛔ **맨몸으로 두면 사진의 원래 치수가 창 크기를 몰고 간다** — 4032×3024짜리가
                //    자기 크기를 「알맞은 크기」로 내놓는다. 그래서 **가로/세로에 따라 창이 달라졌다.**
                //    ✅ **자리를 다 쓰게 못 박으면** 사진은 그 안에서 맞춰지고 **창은 안 흔들린다.**
                //    ⚠️ 시트 쪽 `ideal`과 **둘이 함께** 이 일을 막는다(`DetailView`) — 한쪽만으로는 부족하다.
                img.resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// **「내려받는 중」** — 뷰어를 열거나 넘긴 그 장을 **받아오는 동안만** 뜬다 (2026-08-26 사용자 결정).
    ///
    /// ## ★ 왜 생겼나
    /// 사용자: *"뷰어 열면 사진을 다운로드 하잖아? 그 때 빙글빙글 도는 원 아이콘 하나를 띄워줘.
    /// 그래야 뭔가 받고 있구나 하고 느낄거잖아? 아니면 메시지도 토스트 방식으로 띄워주면 좋고."*
    /// **토스트를 골랐다.**
    ///
    /// ## 15초가 지나면 사라진다 (사용자 결정: *"도는 것만 멈춘다"*)
    /// `timedOut`이 서면 토스트가 없어지고 **구름 아이콘만 남는다.** ⛔ **새 문구를 안 만들었다** —
    /// 「아직 못 받음」이라는 뜻은 **카드 테두리(앰버)가 이미 말하고 있다.**
    ///
    /// ## ★ 꼴과 문구는 **`DownloadToast`로 옮겼다** (2026-08-26 낮)
    /// 같은 표시가 **상세에도** 필요해졌다(「미리보기 다시 받기」). ⛔ 여기 두면 **복제가 셋이 된다.**
    /// *(옛 서술: "**꼴만 따라 여기 따로 만들었다** … ⚠️ **한쪽을 고치면 다른 쪽은 안 따라온다**(복제다)."
    ///  — **그 경고가 이틀 만에 걸려서** 모았다.)*
    @ViewBuilder private var downloadToast: some View {
        if fetch.state == .notDownloaded, !fetch.timedOut {
            DownloadToast()
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
            // ★ **지도 판이 열려 있을 때만 위로 올린다** (2026-10-07 사용자: *"지도 판에 버튼이 반쯤 겹쳐 보여.
            //   지도 닫으면 지금처럼 버튼이 위치하도록 되돌려주고."*) — 판 높이의 절반만큼 올리면
            //   **판 위에 남는 공간의 가운데**에 온다. 닫히면 0으로 돌아온다(같은 애니메이션).
            // ★★ **얼마나 올리나 = 「지도에 안 가린 사진 부분」의 세로 가운데** (2026-10-07 17:5x 사용자:
            //   *"너무 많이 올렸다. 지도가 가리지 않은 사진 영역의 세로 중간 지점까지만 올려줘."*)
            //   ⛔ 첫 판(`14cdc92`)은 **화면** 위쪽 공간의 가운데(판 높이의 절반 = 182pt)로 올렸다 — 기준이 틀렸다.
            //   사진은 `scaledToFit`이라 가로 사진이면 화면 가운데 띠만 차지한다. 그 띠에서 판에 가린 아래를
            //   뺀 나머지의 가운데가 답이다 → 사진 비율·뷰 크기로 계산한다(`arrowLift`).
            .offset(y: arrowLift)
            .animation(Self.fade, value: showPlace)
        }
    }

    /// 지도 판이 열렸을 때의 세로 자리들 — 사진 위·아래(`scaledToFit`이 그리는 대로 · 밀기 전) · 판 꼭대기. 판이 닫혀 있거나 아직 모르면 nil.
    /// ⚠️ `panelTop`은 **옛 어림값**(`placePanelHeight`)이다 — `arrowLift`가 그것으로 서 있고 사용자가 *"< > 위치도 지금이
    /// 적절해. 수정하지 말자"*(19:2x)라 했으므로 **단추 계산은 안 건드린다.** 사진 밀기는 `measuredPanelTop`을 쓴다.
    private var placeGeometry: (photoTop: CGFloat, photoBottom: CGFloat, panelTop: CGFloat)? {
        guard showPlace, viewSize.height > 0, viewSize.width > 0, let a = imageAspect else { return nil }
        let h = viewSize.height
        let fitted = min(h, viewSize.width * a)                 // scaledToFit이 그리는 사진 세로
        let top = (h - fitted) / 2
        return (top, top + fitted, h - Self.placePanelHeight)
    }

    /// 판 꼭대기 — **잰 높이**로(없으면 어림값). 사진 밀기(`photoLift`)만 쓴다.
    private var measuredPanelTop: CGFloat {
        let panel = measuredPanelHeight > 0 ? measuredPanelHeight + Self.placePanelBottom : Self.placePanelHeight
        return viewSize.height - panel
    }

    /// `‹` `›`를 올리는 양(음수 = 위). 지도 판이 닫혀 있거나 판이 사진을 안 가리면 0.
    /// ⚠️ **밀기 전 사진 자리로 센다**(`photoLift`를 안 본다) — 2026-10-07 19:1x 사용자: *"< > 기호는 더 이상 바꾸지 말아봐. 다 보고 다시 조절하자."*
    private var arrowLift: CGFloat {
        guard let g = placeGeometry else { return 0 }
        let visibleBottom = min(g.photoBottom, g.panelTop)
        guard visibleBottom > g.photoTop else { return 0 }
        return (g.photoTop + visibleBottom) / 2 - viewSize.height / 2
    }

    /// ★ **사진을 밀어 올리는 양**(음수 = 위) — 2026-10-07 19:1x 사용자: *"사진 윗쪽에 공간이 있으면 사진을 좀 위로
    /// 밀어올려도 되지 않을까? 가로 사진은 공간이 많이 남고 세로 사진도 공간이 좀 있는 것 같아."*
    /// 판에 가린 만큼 올리되 **사진 위쪽에 남은 공간 이상은 안 올린다**(사진 꼭대기가 화면 위를 넘지 않게).
    /// 가로 사진은 대개 전부 드러나고, 세로 사진은 위에 붙은 뒤에도 아래가 조금 가릴 수 있다. 판이 닫히면 0.
    private var photoLift: CGFloat {
        guard let g = placeGeometry else { return 0 }
        let hidden = g.photoBottom - measuredPanelTop           // ← 잰 값(어림값은 가로 사진 아래가 ~23pt 겹쳤다)
        guard hidden > 0 else { return 0 }
        return -min(hidden, max(0, g.photoTop))
    }

    /// 사진 파일의 세로/가로 비율 — 픽셀 수만 읽는다(그림을 안 푼다) · EXIF 방향 5~8이면 가로세로를 바꾼다.
    private static func aspect(of url: URL) -> CGFloat? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat, let hh = props[kCGImagePropertyPixelHeight] as? CGFloat,
              w > 0, hh > 0 else { return nil }
        let o = props[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(o) ? w / hh : hh / w
    }

    /// 지도 판이 차지하는 세로 — 지도 260 + 안 여백 12×2 + 썸네일 줄 자리(56 + 16 + 8). `placePanel`과 같은 수여야 한다.
    private static let placePanelHeight: CGFloat = 260 + 24 + placePanelBottom
    /// 판 아래 틈 = 썸네일 줄 자리(56 + 16) + 8. `placePanel`의 `padding(.bottom)`과 같은 수여야 한다.
    private static let placePanelBottom: CGFloat = thumbSide + 16 + 8

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
                                    // ★ **X는 네모 「위에」 얹은 형제다** — `label:` 안에 두면
                                    //   SwiftUI가 **바깥 단추의 일부**로 읽어 따로 눌리지 않는다.
                                    ZStack(alignment: .topTrailing) {
                                        Button { pick(i) } label: { thumb(n, selected: i == index) }
                                            .buttonStyle(.plain)
                                        if onDelete != nil { deleteBadge(i) }
                                    }
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

    /// **썸네일 우측 상단의 빨간 X** — 자리와 방식 모두 사용자가 정했다(2026-09-03:
    /// *"뷰어 들어가서 아래 썸네일 목록에서 지우는 방식으로 하고 썸네일 우측 상단에 빨간 X표시를 붙여서
    /// 그걸 누르면 지우게 해줘. 지울 때는 확인 팝업 띄워주고."*).
    ///
    /// ⛔ **새 꼴을 안 지었다** — **`xmark` + `Palette.overdue` + `.semibold`**는 URL 지우기가
    /// 이미 쓰는 꼴이고(`URLPickSheet`), **어두운 동그라미 바탕**은 뷰어의 닫기 단추가 쓰는 꼴이다.
    /// ⚠️ **바탕이 필요한 이유는 여기가 사진 위라는 것이다** — 밝은 사진에서는 빨강만으로는 묻힌다
    /// (URL 목록은 어두운 줄 위라 바탕이 필요 없었다 · 그쪽 주석에 대비 실측이 있다).
    ///
    /// ## ⚠️ 표적이 44pt가 못 된다 — **30pt다** (계측 규칙 1: 권장 표적은 44pt)
    /// **네모 자체가 56pt**인데(사용자가 판정한 값) 그 안에 44pt 표적을 두면
    /// **네모를 고르는 손댐을 거의 다 먹는다** — 「사진을 고르려는데 지우기가 눌린다」가 된다.
    /// ✅ **그래서 30pt로 줄이고 자리를 모서리에 뒀다** — 고르기와 지우기가 갈린다.
    /// ⛔ **이것은 「덮는 값」이 아니라 받아들인 대가다** — 잘못 눌러도 **확인 팝업이 막는다.**
    private static let badgeSide: CGFloat = 30

    @ViewBuilder private func deleteBadge(_ i: Int) -> some View {
        Button { deleting = i } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.overdue)
                .frame(width: Self.badgeSide, height: Self.badgeSide)
                .background(Circle().fill(.black.opacity(0.55)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // 모서리에 살짝 걸치게 — 네모 안쪽으로 2pt만 들여 놓는다(줄이 잘리지 않는 자리).
        .offset(x: 2, y: -2)
    }

    @ViewBuilder private func thumb(_ name: String, selected: Bool) -> some View {
        let img = photoURL(name).flatMap { MediaCard.thumbnail($0, side: Self.thumbSide) }
        ZStack {
            if let img {
                img.resizable().scaledToFill()
            } else {
                // 파일이 없거나 그림을 못 만든 것 — 카드와 같은 뜻만 보인다(새 문구를 안 짓는다).
                Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: Self.thumbSide, height: Self.thumbSide)
        .overlay(alignment: .bottomTrailing) {
            // 카드 네모(§0 18번)와 같은 핀, 같은 자리 — **장마다** 위치가 있나를 갈라 보인다(2026-09-30).
            if coordinate(name) != nil {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: Self.thumbSide * 0.24))
                    .foregroundStyle(.white, .black.opacity(0.45))
                    .padding(Self.thumbSide * 0.05)
            }
        }
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
