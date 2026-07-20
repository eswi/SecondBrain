import SwiftUI

/// 앱 루트 — 하단 탭바와 다크 테마. 세 영역 용어로 통일(memory-philosophy.md §5):
/// 새로운 기억 · 검색 · **살아있는 기억**(가운데, 앱의 심장) · 보관된 기억 · 설정.
/// 모든 탭이 하나의 InboxModel을 공유(같은 병합 데이터).
struct RootView: View {
    @StateObject private var model = InboxModel()
    @ObservedObject private var launcher = CaptureLauncher.shared   // 액션 버튼/단축어 수집 신호
    // 마지막 머문 탭을 결정적으로 복원(재진입 시 탭이 튀지 않게). @State는 iOS 화면상태 복원과 충돌.
    @SceneStorage("selectedTab") private var tab: AppTab = .new
    @Environment(\.scenePhase) private var scenePhase

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
        // 자동 스윕 토스트 — 어느 탭에 있든 **화면 중앙**에 뜬다(설정으로 안 끌고 감).
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
        .onAppear { model.load() }
        // 앱 열 때 미분류를 모아 자동 분류(사양서 §0-A: 백그라운드는 iOS 제약 → "앱 열 때 모아 분류"가 현실적).
        // 키가 있고 미분류가 있을 때만. classifyUnclassified가 .running을 중복 차단(메인 액터 직렬화).
        .task { autoClassify() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { autoClassify() } }
        // 액션 버튼/단축어로 열린 수집 — 새로운 기억 탭으로 옮기고 시트 표시(STT 자동 시작).
        .onChange(of: launcher.showCapture) { _, show in if show { tab = .new } }
        .sheet(isPresented: $launcher.showCapture) { CaptureSheet(model: model) }
    }

    /// 앱 열 때 스윕 — 키·미분류가 있을 때만 분류를 걸어둔다. 진행은 상단 토스트(auto:true).
    private func autoClassify() {
        guard KeychainStore.hasKey, !model.unclassifiedItems.isEmpty else { return }
        Task { await model.classifyUnclassified(auto: true) }
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
