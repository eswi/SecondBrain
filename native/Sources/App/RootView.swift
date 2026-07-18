import SwiftUI

/// 앱 루트 — 하단 탭바(받은함 · 검색 · [+] · 보관함 · 원칙)와 다크 테마.
/// 모든 탭이 하나의 InboxModel을 공유(같은 병합 데이터).
struct RootView: View {
    @StateObject private var model = InboxModel()
    @State private var tab: AppTab = .inbox

    var body: some View {
        TabView(selection: $tab) {
            InboxView(model: model, goToPrinciples: { tab = .principle })
                .tag(AppTab.inbox)
                .tabItem { Label("받은함", systemImage: "tray.fill") }

            SearchView(model: model)
                .tag(AppTab.search)
                .tabItem { Label("검색", systemImage: "magnifyingglass") }

            CapturePlaceholderView()
                .tag(AppTab.capture)
                .tabItem { Label("수집", systemImage: "plus.circle.fill") }

            ArchiveView(model: model)
                .tag(AppTab.archive)
                .tabItem { Label("보관함", systemImage: "archivebox.fill") }

            PrincipleView(model: model)
                .tag(AppTab.principle)
                .tabItem { Label("원칙", systemImage: "star.fill") }
        }
        .tint(Palette.accent)
        .preferredColorScheme(.dark)
        .onAppear { model.load() }
    }
}

enum AppTab: Hashable { case inbox, search, capture, archive, principle }

/// [+] 수집 — 다음 단계. 지금은 자리만.
struct CapturePlaceholderView: View {
    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 52)).foregroundStyle(Palette.textTertiary)
                Text("수집은 곧 나옴").font(.headline).foregroundStyle(Palette.textSecondary)
                Text("음성·타이핑·URL·이미지로\n빠르게 담는 화면을 준비 중이에요.")
                    .font(.callout).foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
