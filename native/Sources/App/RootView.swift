import SwiftUI

/// 앱 루트 — 하단 탭바와 다크 테마. 세 영역 용어로 통일(memory-philosophy.md §5):
/// 새로운 기억 · 검색 · **살아있는 기억**(가운데, 앱의 심장) · 보관된 기억 · 설정.
/// 모든 탭이 하나의 InboxModel을 공유(같은 병합 데이터).
struct RootView: View {
    @StateObject private var model = InboxModel()
    @ObservedObject private var launcher = CaptureLauncher.shared   // 액션 버튼/단축어 수집 신호
    @State private var tab: AppTab = .new

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
        .onAppear { model.load() }
        // 액션 버튼/단축어로 열린 수집 — 새로운 기억 탭으로 옮기고 시트 표시(STT 자동 시작).
        .onChange(of: launcher.showCapture) { _, show in if show { tab = .new } }
        .sheet(isPresented: $launcher.showCapture) { CaptureSheet(model: model) }
    }
}

enum AppTab: Hashable { case new, search, living, archive, settings }
