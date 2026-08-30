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
        TabView(selection: $tab) {
            InboxView(model: model)
                .tag(AppTab.new)
                .tabItem { Label("새로운 기억", systemImage: "tray.fill") }

            SearchView(model: model)
                .tag(AppTab.search)
                .tabItem { Label("검색", systemImage: "magnifyingglass") }

            LivingView(model: model)
                .tag(AppTab.living)
                .tabItem { Label("살아있는 기억", systemImage: "heart.fill") }

            ArchiveView(model: model)
                .tag(AppTab.archive)
                .tabItem { Label("보관된 기억", systemImage: "archivebox.fill") }

            SettingsView(model: model)
                .tag(AppTab.settings)
                .tabItem { Label("설정", systemImage: "gearshape.fill") }
        }
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
        .sheet(isPresented: $launcher.showCapture, onDismiss: { hotkeyCaptureClosed() }) {
            CaptureSheet(model: model, origin: .hotkey)
        }
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
    }

    /// **핫키로 열린 수집이 닫혔다** — 어떻게 닫혔는지에 따라 갈린다(2026-08-31 사용자 결정).
    ///
    /// | 어떻게 닫혔나 | 무엇을 하나 |
    /// |---|---|
    /// | **`<`** | 아무것도 안 한다 — **「새로운 기억」에 남는다**(사용자가 정한 자리) |
    /// | **[취소하기]** · 앱이 **이미 떠 있었다** | **그때 보던 탭으로 되돌리고** 내려놓는다(`suspend`) |
    /// | **[취소하기]** · 핫키가 **앱을 깨웠다** | **끝낸다**(`exit(0)`) — *"아예 앱이 exit 상태였다면 exit상태로"* |
    ///
    /// ⛔ **왜 여기인가:** 되돌릴 탭을 아는 곳이 여기다. **시트에서 내려놓으면 되돌리기 전에
    /// 화면이 얼어 수집 화면이 남은 채로 내려간다.**
    /// ⚠️ **`likelyWokenByHotkey`는 추정이다** — 문턱 3초의 근거와 오판의 방향은 그 프로퍼티 주석에.
    /// ⛔ **`exit(0)`은 크래시로 기록된다** — 사용자가 *"exit상태로"*를 명시해서 쓴다.
    ///   ⚠️ **파일 쓰기는 이미 끝나 있다** — 수집을 버리고 나가는 길이라 append가 없다.
    private func hotkeyCaptureClosed() {
        #if os(iOS)
        defer { launcher.tabBeforeHotkey = nil; launcher.cancelledOut = false }
        guard launcher.cancelledOut else { return }        // `<`로 닫혔다 → 앱 안에 남는다
        let woken = launcher.likelyWokenByHotkey
        if let back = launcher.tabBeforeHotkey, !woken { setTabNoAnimation(back) }
        if woken {
            exit(0)
        } else {
            // 비공개 선택자 — `#selector`는 공개 API에만 쓸 수 있다. `NSSelectorFromString`은 경고가 없다.
            UIApplication.shared.perform(NSSelectorFromString("suspend"))
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
enum AppTab: String { case new, search, living, archive, settings }
