import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 앱 루트 — 하단 탭바와 다크 테마. 세 영역 용어로 통일(memory-philosophy.md §5):
/// 새로운 기억 · 검색 · **살아있는 기억**(가운데, 앱의 심장) · 보관된 기억 · 설정.
/// 모든 탭이 하나의 InboxModel을 공유(같은 병합 데이터).
struct RootView: View {
    @StateObject private var model = InboxModel()
    @ObservedObject private var launcher = CaptureLauncher.shared   // 액션 버튼/단축어 수집 신호
    // 마지막 머문 탭을 재실행/scene 복원 사이에 유지.
    @SceneStorage("selectedTab") private var tab: AppTab = .new
    @Environment(\.scenePhase) private var scenePhase
    // 마지막으로 "사용자가" 고른 탭. 홈으로 나가려 화면 하단을 쓸어 올릴 때, iOS가 그 제스처를
    // 홈 제스처로 확정하기 직전까지 터치가 앱에 전달돼 손가락이 스친 탭바 버튼이 선택돼 버린다
    // (실기기 A/B로 확정: 터치 없이 백그라운드로 보내면=전원버튼 안 튐, 홈스와이프만 튄다).
    // 이 우발적 선택은 scene이 .active가 아닐 때 들어오므로 onChange에서 걸러 이 값엔 반영하지 않고,
    // 나가는 즉시(그리고 복귀 시 보강) 이 값으로 되돌린다. 시스템 제스처라 원천 차단은 불가.
    @State private var stableTab: AppTab = .new


    var body: some View {
        // ★★ **런치 옵션으로 들어왔으면 수집 화면이 「뿌리」다** (2026-08-31).
        //    ⛔ **띄우지 않는다** — `fullScreenCover`는 한 프레임 뒤에 올라와 **목록이 짧게 스쳤다**
        //    (사용자: *"짧은 시간동안 새로운 기억 화면이 띄긴 하네. 짧게."*).
        //    **`ZStack`의 형제로 그리면 같은 프레임에 나오므로 스칠 자리가 없다.**
        //    ⚠️ **따뜻한 진입(이미 떠 있는데 URL이 옴)은 여기 안 온다** — 그쪽은 아래 `fullScreenCover`다.
        ZStack {
            mainBody
            #if os(iOS)
            // ★★ **끝내는 길에서는 `showCapture`가 안 내려간다** — 그래서 이 조건이 그대로 참이고
            //   **수집 화면이 마지막까지 그려진 채로** 미끄러져 내려간다(`CaptureSheet.leaveNow`).
            //   ⛔ **옛 시도(하루 만에 걷어냈다): `holdForExit`** — 내려간 **뒤에** 다시 붙잡으려 했고
            //   **`suspend`가 그보다 빨랐다**(사용자: *"3번은 전혀 안 바뀌었음"*).
            if launcher.showCapture && launcher.launchedByURL {
                CaptureSheet(model: model, origin: .hotkey)
                    .background(Palette.bg.ignoresSafeArea())
                    .transition(.identity)          // 나타날 때 움직임이 없어야 「처음부터 있던 것」이 된다
            }
            #endif
        }
    }

    /// ## ⛔⛔ 가로 좌우 여백 줄이기 — **만들었다가 되돌렸다. 되살리려면 아래를 먼저 읽을 것** (2026-09-13)
    ///
    /// 사용자: *"가로 모드에서는 화면의 좌우 여백이 너무 커 … 우측 여백은 너무 커서 다 줄어야 해."*
    ///
    /// **쟀다(앱 로그):** iOS가 가로에서 **좌우 각각 62pt**를 준다 — **대칭이다.**
    /// ⛔ **대칭인 이유:** 섬(Dynamic Island)이 **돌리는 방향에 따라 좌·우 어느 쪽에도 온다.**
    /// 실제로 양쪽을 다 없애 보니 **「살아있는 기억」이 섬에 잘려 「살이 … 억」**이 됐다.
    ///
    /// **그래서 「섬이 없는 쪽만」 되찾게 만들었다**(`interfaceOrientation`으로 가려서
    /// `@State freeSide` → `.ignoresSafeArea(edges:)`). **돌아갔다** — 한 방향에서
    /// 오른쪽 여백이 사라지고 띠가 화면 끝에 붙는 것을 시뮬에서 확인했다.
    ///
    /// ⛔⛔ **그런데 폰에서 화면이 얼었다** (사용자: *"화면이 자꾸 죽어"*). **재현·확인했다:**
    /// 시뮬에서 **연달아 여섯 번 돌리니 화면이 멎었다**(프로세스는 살아 있고 그림만 안 바뀐다).
    /// **그 배선만 빼고 같은 시험을 하니 여덟 번 돌려도 안 언다.**
    /// ★ **원인은 되울림이다** — `.onChange(of: geo.size)`가 상태를 바꾸고,
    /// 그 상태가 **그 `GeometryReader`의 크기를 바꾼다.** 값이 같으면 멈추게 막아 뒀는데도
    /// 회전 중에는 방향과 크기가 **엇갈려 들어와** 고리가 돈다.
    ///
    /// ▶ **다시 할 때의 길:** ⛔ **크기 변화에 상태를 물리지 말 것.** 방향은
    /// `orientationDidChangeNotification`처럼 **레이아웃 밖의 신호**로 받는다.
    /// ⚠️ **그리고 내용 쪽은 그것으로도 안 줄어든다** — 바깥 칸은 넓어지는데
    /// (`size 750 → 812` · `insets L62 → L0`) **`TabView`·`NavigationStack`이 자식에게
    /// 안전영역을 다시 넣는다.** 줄이려면 **화면 다섯 각각의 목록까지** 내려가야 한다.
    ///
    /// **가로면 시스템 탭바를 숨기고 세로 띠를 형제로 세운다** (2026-09-13 사용자 결정).
    /// 왜 형제인가·무엇을 골랐나 → `SideTabBar` 머리주석.
    /// ⚠️ **세로는 건드리지 않았다** — 시스템 탭바 그대로다(모습·자리·여백 전부).
    @ViewBuilder private var tabShell: some View {
        #if os(iOS)
        GeometryReader { geo in
            // 가로·세로는 **실제 칸 모양**으로 가른다. ⛔ `horizontalSizeClass`로 가르지 말 것 —
            // 기기마다 다르게 나온다(Max는 가로에서도 `.regular`인 경우가 있다).
            let landscape = geo.size.width > geo.size.height
            HStack(spacing: 0) {
                tabs(landscape: landscape)
                if landscape {
                    SideTabBar(tab: $tab).frame(width: SideTabBar.thickness)
                }
            }
            // ★★ **섬이 없는 쪽의 안전영역은 순전한 여백이다 — 그쪽만 되찾는다** (2026-09-13).
            //   사용자: *"가로 모드에서는 화면의 좌우 여백이 너무 커."*
            //   **쟀다(시뮬 26.5 · 두 회전 다):** 카드 왼쪽 끝이 **양쪽 다 72pt** — 즉 iOS가
            //   **좌우 안전영역을 대칭으로** 준다(≈56pt + 우리 여백 16pt).
            //   ⛔ **대칭인 이유가 있다: 섬(Dynamic Island)이 돌리는 방향에 따라 좌·우 어느 쪽에도 온다.**
            //   그래서 **양쪽을 다 없애면 한 방향에서 글자가 섬에 가린다.**
            //   ✅ **한쪽은 늘 순전한 여백이다** — 섬이 없는 쪽. 그쪽만 없앤다.
        }
        #else
        tabs(landscape: false)
        #endif
    }



    private func tabs(landscape: Bool) -> some View {
        TabView(selection: $tab) {
            InboxView(model: model)
                .tag(AppTab.new)
                .tabItem { Label(AppTab.new.title, systemImage: AppTab.new.icon) }
                .modifier(SystemTabBarHidden(hidden: landscape))

            SearchView(model: model)
                .tag(AppTab.search)
                .tabItem { Label(AppTab.search.title, systemImage: AppTab.search.icon) }
                .modifier(SystemTabBarHidden(hidden: landscape))

            LivingView(model: model)
                .tag(AppTab.living)
                .tabItem { Label(AppTab.living.title, systemImage: AppTab.living.icon) }
                .modifier(SystemTabBarHidden(hidden: landscape))

            ArchiveView(model: model)
                .tag(AppTab.archive)
                .tabItem { Label(AppTab.archive.title, systemImage: AppTab.archive.icon) }
                .modifier(SystemTabBarHidden(hidden: landscape))

            SettingsView(model: model)
                .tag(AppTab.settings)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.icon) }
                .modifier(SystemTabBarHidden(hidden: landscape))
        }
    }

    private var mainBody: some View {
        tabShell
        .tint(Palette.accent)
        .preferredColorScheme(.dark)
        // 당겨서 분류(pull-to-classify) 결과 토스트 — 어느 탭에 있든 **화면 중앙**에 뜬다.
        // 터치는 안 막는다(allowsHitTesting=false) → 밑 화면 계속 조작 가능.
        .overlay {
            if let toast = model.autoToast {
                ClassifyToastView(toast: toast)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(duration: 0.3), value: model.autoToast)
        // 리스트(스와이프·컨텍스트) 삭제 재확인 — 어느 탭이든 여기 한 곳에서 공용 팝업으로 처리.
        // 상세 화면 [삭제하기]는 자체 확인(dismiss 필요)이라 이 경로를 쓰지 않는다.
        .overlay {
            if let pending = model.pendingDelete {
                ConfirmDialog(title: "정말로 삭제하시겠습니까?",
                              confirmTitle: "삭제", confirmTint: Palette.overdue,
                              onCancel: { model.pendingDelete = nil },
                              onConfirm: { model.delete(pending); model.pendingDelete = nil })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.pendingDelete)
        // 성공·실패 토스트는 잠시 뒤 자동으로 사라짐(진행 중 토스트는 다음 상태가 대체).
        .onChange(of: model.autoToast) { _, new in
            guard let t = new, t.kind != .running else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if model.autoToast == t { model.autoToast = nil }
            }
        }
        // 초기 로드(백그라운드 I/O). load I/O가 메인 밖이라 이 await 동안에도 UI는 안 막힌다.
        // 분류는 자동으로 걸지 않는다 — 사용자가 "새로운 기억"을 아래로 당길 때만(pull-to-classify, §0-A).
        .task {
            await model.reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // 복귀 보강: 나가는 순간 못 잡았거나 프레임워크가 다시 덮어썼으면 여기서 원복(무애니메이션).
                if tab != stableTab { setTabNoAnimation(stableTab) }
                // **복귀 시 재등록(Stage 5-C, 2026-08-06).** 여기까지 `reload()`는 콜드 런치(`.task`)와
                // 로컬 행동에서만 돌았다 → **포그라운드 복귀만으로는 알림이 갱신되지 않았고**, 그래서 아침
                // 7시 약은 *그 전에 앱을 열어둔 날에만* 알림이 왔다. 체인의 신선도가 이 빈도에 걸려 있어
                // 체인만 넣고 이걸 안 고치면 절반짜리다(§9 실측 구멍 2).
                // 멱등하고(전량 재등록) I/O는 백그라운드라 자주 돌아도 안전하다.
                Task { await model.reload() }
            }
        }
        // 액션 버튼/단축어로 열린 수집 — 새로운 기억 탭으로 옮기고 시트 표시(STT 자동 시작).
        // ★ **그 순간의 탭을 적어 둔다** — [취소하기]로 나갈 때 **그 화면으로 되돌린 뒤** 내려놓는다
        //   (2026-08-31 사용자: *"앱이 그 전에 suspend되어 있던 화면 상태로 suspend"*).
        .onChange(of: launcher.showCapture) { _, show in
            if show {
                if launcher.tabBeforeHotkey == nil { launcher.tabBeforeHotkey = tab }
                tab = .new
            }
        }
        // ⛔ **`origin: .hotkey`** — 이 시트는 **앱 밖(액션 버튼·단축어)에서** 열린 것이다.
        //    `<`는 있고(「새로운 기억」으로) **[취소하기]가 앱 밖으로** 나간다(`CaptureOrigin`).
        // ★★ **핫키 진입은 시트가 아니라 「전체 화면」이다** (2026-08-31).
        //    ⛔ **시트는 카드처럼 목록 위에 얹혀 아래가 보인다** — *"바로 수집화면으로"*가 안 된다.
        //    `fullScreenCover`는 **탭바까지 덮어** 그 자체가 화면이 된다.
        //    ⚠️ **앱 안의 `+`는 그대로 시트다**(`InboxView`) — 그쪽은 **되돌아갈 화면이 있고**
        //    카드처럼 얹히는 것이 맞다. **두 진입이 다르게 보이는 것이 뜻과 맞는다.**
        //    ⚠️ **런치 옵션으로 들어온 것은 여기 안 온다** — 그것은 위 `ZStack`에서 **뿌리로** 그려진다.
        //    이 커버는 **이미 떠 있는 앱에 URL·인텐트가 온 경우**만 맡는다.
        #if os(iOS)
        .fullScreenCover(isPresented: warmCapture) { CaptureSheet(model: model, origin: .hotkey) }
        #else
        .sheet(isPresented: warmCapture) { CaptureSheet(model: model, origin: .hotkey) }
        #endif
        // ★ **닫힘 처리를 한 자리로 모았다** — 뿌리로 그려질 때는 `onDismiss`가 없다(띄운 것이 아니다).
        //   ⛔ 두 자리에 두면 한쪽만 돌아 「앱 밖으로」가 빠진다.
        .onChange(of: launcher.showCapture) { _, now in if !now { hotkeyCaptureClosed() } }
        // ★★ **[취소하기]는 이 값으로 온다** (2026-09-02) — 끝내는 길에서는 `showCapture`가
        //   **안 내려가므로** 위 줄이 안 돈다. ⚠️ **둘 다 도는 경우가 있다**(앱 안에 머무는 길) —
        //   먼저 도는 쪽이 `cancelledOut`을 내리므로 **뒤엣것은 guard에서 되돌아 나간다.**
        .onChange(of: launcher.cancelledOut) { _, now in if now { hotkeyCaptureClosed() } }
        .onChange(of: tab) { _, newTab in
            if scenePhase == .active {
                // 사용자가 실제로 고른 탭(active일 때만 일어남) → 기억.
                stableTab = newTab
            } else if newTab != stableTab {
                // 나가는 중 홈 제스처가 탭바를 스쳐 생긴 우발적 선택 → 화면 밖일 때 즉시 원복(무애니메이션).
                // (onChange는 상태 확정 뒤 실행돼 이 시점 scene이 .active가 아님이 보장된다.)
                setTabNoAnimation(stableTab)
            }
        }
        .onAppear { stableTab = tab }   // 최초 진입: 복원된 탭을 기준값으로
        // ⛔⛔ **「시간 문」을 걷어냈다** (2026-08-31 · 사용자가 방향을 바로잡았다).
        //    **옛 꼴(지우지 않고 적어 둔다):** 뜬 직후 **120ms를 바탕색으로 덮어** 목록이 스치는 것을
        //    막으려 했다. **여전히 스쳤다** — 인텐트가 그보다 늦게 온다.
        //    ⛔ **그리고 값을 재서 늘리는 것도 답이 아니었다** — 사용자:
        //    *"시간을 재는 방식을 써야 하는거야?"* → **아니다.**
        //    ✅ **답은 「앱을 띄울 때 옵션을 주는 것」**이고 그 자리가 **URL 스킴**이다
        //    (`AppLaunchOptions` · `secondbrain://capture`). **첫 프레임 전에 알 수 있으므로 문이 필요 없다.**
        //    ⚠️ **문은 보통 실행도 120ms 늦추고 있었다** — 걷어내면서 그 대가도 사라졌다.
        // 앱이 떠 있는 동안 같은 URL로 다시 들어오는 길(따뜻한 진입) — 런치 옵션은 델리게이트가 본다.
        #if os(iOS)
        .onOpenURL { AppLaunchOptions.handle($0) }
        #endif
    }

    /// **따뜻한 진입만 띄운다** — 런치 옵션으로 온 것은 뿌리로 그려지므로 여기서 제외한다.
    /// ⚠️ **끌 때는 `showCapture`를 내린다** — 그러면 뿌리 갈래와 커버 갈래가 **같은 값 하나**로 닫힌다.
    private var warmCapture: Binding<Bool> {
        Binding(get: { launcher.showCapture && !launcher.launchedByURL },
                set: { if !$0 { launcher.showCapture = false } })
    }

    /// **핫키로 열린 수집이 닫혔다** — 어떻게 닫혔는지에 따라 갈린다(2026-08-31 사용자 결정).
    ///
    /// | 어떻게 닫혔나 | 무엇을 하나 |
    /// |---|---|
    /// | **`<`** | 아무것도 안 한다 — **「새로운 기억」에 남는다**(사용자가 정한 자리) |
    /// | **[취소하기]** · 앱이 **이미 떠 있었다** | **그때 보던 탭으로 되돌리고** 내려놓는다(`suspend`) |
    /// | **[취소하기]** · 핫키가 **앱을 깨웠다** | **끝낸다**(`exit(0)`) — *"아예 앱이 exit 상태였다면 exit상태로"* |
    ///
    /// ★★ **한 줄로 하면 이것이다** (2026-09-02 사용자):
    /// *"액션 버튼으로 들어간 경우는 **들어가기 직전 앱의 상태를 봐뒀다가 취소하고 나올 때 그 상태로**
    /// 만들어달라는거야."* — 위 표의 두 줄은 **그 한 원칙의 두 경우**다.
    /// ⚠️ **떠 있던 경우는 「그 화면이 그대로 보여도 괜찮다」**고 사용자가 명시했다
    /// (*"앱을 완전 종료시킬 필요도 없고"*) — **되돌릴 상태가 「살아 있음」이기 때문**이다.
    ///
    /// ⛔ **왜 여기인가:** 되돌릴 탭을 아는 곳이 여기다. **시트에서 내려놓으면 되돌리기 전에
    /// 화면이 얼어 수집 화면이 남은 채로 내려간다.**
    /// ✅ **「깨웠나」는 이제 추정이 아니다** — `wokenByHotkey`(= `launchedByURL`)가 그 사실이다.
    /// ⛔ **옛 서술: *"`likelyWokenByHotkey`는 추정이다 — 문턱 3초…"*** (2026-09-02에 죽었다).
    /// ⛔ **`exit(0)`은 크래시로 기록된다** — 사용자가 *"exit상태로"*를 명시해서 쓴다.
    ///   ⚠️ **파일 쓰기는 이미 끝나 있다** — 수집을 버리고 나가는 길이라 append가 없다.
    private func hotkeyCaptureClosed() {
        #if os(iOS)
        // ⚠️ **`woken`을 defer보다 먼저 정한다** — defer가 이 값에 걸린다.
        let woken = launcher.cancelledOut && launcher.wokenByHotkey
        defer {
            launcher.tabBeforeHotkey = nil
            launcher.cancelledOut = false
            // ★ **끝내는 길이면 뿌리를 그대로 둔다** (2026-09-02) — 내리면 목록이 드러난다.
            if !woken { launcher.launchedByURL = false }   // 뿌리 갈래를 내려 목록이 다시 보이게
        }
        guard launcher.cancelledOut else { return }        // `<`로 닫혔다 → 앱 안에 남는다
        if let back = launcher.tabBeforeHotkey, !woken { setTabNoAnimation(back) }
        // ★★★ **끝내는 신호를 「지연」에서 「알림」으로 옮겼다** (2026-09-13 · 후보 첫째를 밟는다).
        //
        //   ⛔ **밟은 길 셋이 다 실패했다** (`docs/worklog/2026-09-02-macmini.md` §3).
        //   마지막이 **`beginBackgroundTask` + 0.45초 `exit(0)`**이었고 **앱이 안 끝났다**
        //   (사용자: *"깨끗하게 나와지네. 이건 좋아. 그런데.. 앱이 살아있어."* · 전환기에 카드가 남았다).
        //   ★ **증상이 좁혀 줬다 — 화면 쪽은 다 됐고 그 줄만 안 돈다.**
        //   `exit(0)`이 돌면 프로세스는 **반드시** 죽으므로, 안 죽었다는 것은 **안 돌았다**는 뜻이다.
        //   ⛔ **`suspend` 뒤에는 메인 큐가 멈춘다** — 지연 블록은 **영영 안 깨어난다.**
        //   **`beginBackgroundTask`로도 안 열렸다**(⚠️ 왜인지는 **안 쟀다** — 앱이 「스스로」
        //   내려가는 길이라 배경 시간 보증이 안 먹는 것으로 보인다 · **추정**).
        //
        //   ✅ **그래서 기다리는 것을 그만뒀다** — `didEnterBackgroundNotification`은
        //   **내려가는 그 순간**(큐가 아직 도는 동안) 오므로 **지연 블록이 필요 없다.**
        //   ★ **실패의 원인 자체를 비켜간다** — 「멈춘 큐에 일을 얹는 것」을 안 한다.
        //   ⚠️ **`queue:`에 `.main`을 주면 안 된다** — 그러면 블록이 **큐에 얹혀** 같은 자리로
        //   되돌아간다. **`nil`이라야 알림을 보낸 그 실행 흐름에서 곧바로 돈다.**
        //   ⚠️ **모습은 안 바뀐다** — 이 알림은 **내려가는 애니메이션 뒤에** 오므로
        //   08-31에 반려된 「휙 사라져」(*"너무 허무하게 끝나 … 섭섭해"*)로 돌아가지 않는다.
        let app = UIApplication.shared
        if woken {
            //   ⛔ **닫지 않는다**(`endBackgroundTask`) — 이 길의 끝은 `exit(0)`이다.
            //   만료 처리로도 `exit(0)`을 걸어 둔다 — **어느 쪽으로 가든 앱은 끝난다.**
            _ = app.beginBackgroundTask(withName: "capture-exit") { exit(0) }
            //   ★ **한 번만 듣는다** — 이 길은 반드시 끝나 되돌아올 자리가 없지만,
            //   **등록이 남아 다음 배경 진입에서 앱을 끝내는 일이 없게** 토큰을 지운다.
            var token: NSObjectProtocol?
            token = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil, queue: nil
            ) { _ in
                if let t = token { NotificationCenter.default.removeObserver(t) }
                exit(0)
            }
        }
        // 비공개 선택자 — `#selector`는 공개 API에만 쓸 수 있다. `NSSelectorFromString`은 경고가 없다.
        app.perform(NSSelectorFromString("suspend"))
        // ★ **0.45초 지연은 「보루」로만 남긴다** (2026-09-13).
        //   ⛔ **이 줄이 도는 것을 본 적이 없다** — 위에 적은 이유로 큐가 멈춰 있다.
        //   ⚠️ **그래도 안 지운다:** 알림 길이 안 열리는 상황이 있으면 **여기가 유일한 뒤**다.
        //   ✅ **둘이 겹쳐도 해가 없다** — 먼저 도는 쪽이 프로세스를 끝낸다.
        //   ⚠️ **0.45초는 잰 값이 아니라 고른 값이다**(추정) — 내려가는 애니메이션 길이를 **안 쟀다.**
        //   ⛔ **이 값을 손대서 문제를 풀려 하지 말 것** — 「짐작한 상수로 경합을 덮는 것」이
        //   이 자리에서 이미 셋(`350ms`·`120ms`·`3.0s`) 죽었다(08-31 worklog §2).
        if woken {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { exit(0) }
        }
        #endif
    }

    /// 탭을 애니메이션 없이 설정 — 우발적 선택 원복 시 슬라이드가 눈에 보이지 않게.
    private func setTabNoAnimation(_ newTab: AppTab) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { tab = newTab }
    }
}

/// 자동 스윕 **중앙** 토스트 — 진행 중(스피너)·성공(체크)·실패(경고). 커스텀 대화상자 톤과 맞춘 카드.
private struct ClassifyToastView: View {
    let toast: InboxModel.ClassifyToast

    var body: some View {
        VStack(spacing: 14) {
            switch toast.kind {
            case .running:
                ProgressView().controlSize(.large).tint(Palette.accent)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(Palette.accent)
            case .failure:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34)).foregroundStyle(Palette.overdue)
            }
            Text(toast.text)
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(minWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.surface2)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Palette.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
        )
    }
}

// String raw값 → @SceneStorage에 저장 가능(RawRepresentable). 재진입 시 탭 복원용.
enum AppTab: String, CaseIterable {
    case new, search, living, archive, settings

    /// ⛔ **화면에 나오는 말이다 — 내가 짓지 않는다**(항시 규칙 6). 여기 있는 것은
    /// **옮겨 적은 것**이지 새로 지은 것이 아니다(옛 자리 = `RootView`의 `.tabItem` 다섯).
    /// ★ **한 곳으로 모은 이유:** 2026-09-13에 **가로용 세로 띠**가 생기면서 **같은 말을 쓰는 자리가 둘**이
    /// 됐다. 나눠 두면 한쪽만 고쳐져 **「어디는 되고 어디는 안 되는」**이 된다(고칠 때 훑는 법 2).
    var title: String {
        switch self {
        case .new:      return "새로운 기억"
        case .search:   return "검색"
        case .living:   return "살아있는 기억"
        case .archive:  return "보관된 기억"
        case .settings: return "설정"
        }
    }

    var icon: String {
        switch self {
        case .new:      return "tray.fill"
        case .search:   return "magnifyingglass"
        case .living:   return "heart.fill"
        case .archive:  return "archivebox.fill"
        case .settings: return "gearshape.fill"
        }
    }
}


/// **시스템 탭바를 숨길지** — 가로에서 `SideTabBar`가 대신 선다.
/// ⚠️ **맥에는 이 자리(`.tabBar`)가 없다** — 그래서 갈라 두고 맥에서는 아무것도 안 한다.
private struct SystemTabBarHidden: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbar(hidden ? .hidden : .automatic, for: .tabBar)
        #else
        content
        #endif
    }
}


#if os(iOS)
/// **가로에서 왼쪽 여백을 좁힌다** — 시스템이 스스로 쓰는 자리에 맞춘다 (2026-09-13 사용자 지시).
///
/// 사용자: *"가로 모드에서도 좌측 상단의 '< 새로운 기억' 제목이 … 좌측 여백을 **벗어나서** 표시된 것을
/// 참고하여, 모든 화면에서 좌측 여백을 이 스크린샷이 쓰는 영역을 고려하여 좁혀줘."*
///
/// **쟀다**(사용자 폰 스크린샷 · 가로 874x402pt · `measure-ui.swift` @3x):
/// | 무엇 | 왼쪽 끝 |
/// |---|---|
/// | **시스템 「‹ 새로운 기억」 알약** | **≈39pt** |
/// | 우리 카드·제목 | **≈78pt** (안전영역 62 + 우리 여백 16) |
/// ★ **iOS 26은 자기 껍데기를 안전영역 안쪽에 그린다** — 세로의 떠 있는 탭바도 아래 **21pt**에 있다
/// (안전영역 34pt보다 안쪽). **그래서 우리도 그 자리를 쓸 수 있다.**
///
/// ## ⛔⛔⛔ `.ignoresSafeArea`로는 못 한다 — **세 자리에서 다 헛걸었다** (2026-09-13)
/// 그 모디파이어는 **그 칸을 넓힐 뿐, 안쪽 컨테이너가 자식에게 다시 넣는 것은 못 막는다.**
/// | 건 자리 | 결과 |
/// |---|---|
/// | **① `GeometryReader` 바깥**(`tabShell`) | 칸은 넓어졌는데(`size 750 → 812`) **화면은 그대로** |
/// | **② `TabView`의 자식**(화면 통째) | 그대로. **여백만 더해져 오히려 넓어졌다**(쟀다: 96pt) |
/// | **③ `NavigationStack` 안쪽** | **역시 그대로** |
/// ✅ **그래서 「무시」가 아니라 「밀기」로 간다 — 음수 여백.**
/// 안전영역 값을 읽어 **`leading − 23`만큼 왼쪽으로 민다.** 그러면 제목이 **23 + 16 = 39pt**에 앉는다.
///
/// ⚠️ **세로에서는 안 민다** — 크기 등급으로 가른다(`verticalSizeClass == .compact` = 아이폰 가로).
/// 세로의 좌우 안전영역은 0이라 어차피 밀 것도 없다.
/// ⛔⛔ **상태를 쓰지 않는다 — 그것이 오늘 화면을 얼렸다**(전말 → `RootView.tabShell` 머리주석).
/// 창에서 값을 **읽기만** 하고, 회전하면 `verticalSizeClass`가 바뀌어 `body`가 다시 돈다.
///
/// ⚠️ **섬(Dynamic Island) 쪽이면 글자가 가릴 수 있다** — 시스템도 같은 자리를 쓰지만
/// **두 방향 다 확인해야 한다**(설치 이력의 볼 것에 적었다).
private struct LandscapeEdge: ViewModifier {
    @Environment(\.verticalSizeClass) private var vClass

    /// **내용이 시작하는 자리**(화면 왼쪽 끝에서). 화면들의 제 여백(12~16pt)은 여기에 더해진다.
    ///
    /// ## ⛔⛔ 39pt로 잡았다가 되돌렸다 — **노치 밑으로 들어갔다** (2026-09-13 폰 판정)
    /// 사용자: *"스크롤하면 노치 영역까지 컨텐츠가 들어가버려. 원칙 영역의 각 원칙의 항목 바탕의
    /// 왼쪽 편이 노치 안으로 들어가버려."*
    ///
    /// ★★ **왜 시스템은 39pt로 되고 우리는 안 되나 — 높이가 다르다.**
    /// **섬은 화면 가장자리의 「가운데」에만 있다**(실측 y 143 ~ 260pt · 화면 높이 402pt).
    /// 시스템 「‹」 알약은 **맨 위**(y 35~57pt)라 **섬보다 위**에 있어 안 겹친다.
    /// ⛔ **그런데 목록은 섬의 높이를 지나간다** — 그래서 같은 39pt가 여기서는 가린다.
    /// ⚠️ **그 스크린샷 하나만 보고 「시스템이 쓰니 우리도 된다」로 읽은 것이 틀렸다**
    /// (계측 규칙 8 — 조건이 좁으면 값이 아니라 판정이 틀린다. 여기서 좁았던 조건은 **높이**다).
    ///
    /// **쟀다**(시뮬 26.5 가로 · `measure-ui.swift` @3x): **섬의 안쪽 끝 50~52pt**
    /// (48.3pt까지는 섬이 세로로 꽉 차고 50pt부터 둥근 끝이 들어간다).
    /// → **54pt** — 섬 안쪽 끝 + 2pt. **내용이 시작하는 자리 자체를 섬 바깥에 둔다.**
    /// ⛔ **화면마다 제 여백이 다르므로**(12 · 16) **여백에 기대지 않는다** —
    /// 사용자: *"어떤 컨텐츠도 들어가지 않도록."*
    ///
    /// *(옛 값 · 지우지 않는다: **23pt** — 제목이 39pt에 앉게 한 값. 위 이유로 죽었다.)*
    static let extra: CGFloat = 54

    /// 지금 창의 왼쪽 안전영역. ⚠️ **SwiftUI의 의존값이 아니다** — 그래서 이것만으로는 회전에 안 따라온다.
    /// **`vClass`가 같이 바뀌므로** `body`가 다시 돌고, 그때 이 값을 새로 읽는다.
    private var leadingInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets.left ?? 0
    }

    func body(content: Content) -> some View {
        let shift = vClass == .compact ? max(0, leadingInset - Self.extra) : 0
        return content.padding(.leading, -shift)
    }
}
#endif

extension View {
    /// 가로에서 좌우 안전영역을 걷고 시스템과 같은 자리에 맞춘다 — `NavigationStack` **안쪽**에 건다.
    @ViewBuilder func landscapeEdge() -> some View {
        #if os(iOS)
        modifier(LandscapeEdge())
        #else
        self
        #endif
    }
}
