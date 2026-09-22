import SwiftUI
import SecondBrainCore

/// "살아있는 기억" — 앱의 심장(memory-philosophy.md §2-2).
/// 확정을 거쳐 살아남은, 시점 없는 것들(아이디어·지식·직관). 필터는 여기에 있다.
/// (윗단 = "가장 살아있는 것" 정의는 나중에 기획. v1은 필터 + 리스트만.)
struct LivingView: View {
    @ObservedObject var model: InboxModel
    /// **해시태그 필터**(2026-09-22 사용자 결정 · 정본 `tag-filter-design.md`) — 분류 칩을 거친 목록에서 태그를 뽑고 거른다.
    @State private var tagFilter = TagFilter()
    @State private var showTagPanel = false
    @AppStorage(EdgeHandle.topStorageKey) private var edgeHandleTop: Double = -1

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerRow
                FilterChipsBar(filter: $model.filter, presentTypes: model.livingPresentTypes)
                content.overlay {
                    TagFilterDock(topOffset: $edgeHandleTop, filter: $tagFilter, isOpen: $showTagPanel,
                                  items: model.livingMemories)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.bg.ignoresSafeArea())
            .hiddenNavBar()
            .landscapeEdge()
            .navigationDestination(for: DetailRoute.self) { DetailView(item: $0.item, model: model, backTitle: $0.backTitle) }
        }
    }

    private var headerRow: some View { ScreenTitle("살아있는 기억") }

    private var content: some View {
        let items = model.livingMemories
        let shown = tagFilter.pruned(to: TagFilter.available(in: items)).apply(items)   // 해시태그 필터(2026-09-22)
        return List {
            if items.isEmpty {   // ⚠️ 태그 필터 전 기준 — 필터로 전부 숨었을 때는 빈 목록(설계 §2 17번 · 아래 말들은 다른 뜻이다)
                Text(model.filter == .all ? "아직 살아있는 기억이 없어요\n새 기억을 기억하기로 하면 여기로 와요" : "이 종류가 없어요")
                    .font(.callout).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
                    .listRowBackground(Palette.bg).listRowSeparator(.hidden)
            } else {
                ForEach(shown, id: \.id) { item in
                    MemoryRow(item: item, model: model, backTitle: "살아있는 기억")
                        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                        .listRowBackground(Palette.bg).listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { model.pendingDelete = item } label: { Label("삭제", systemImage: "trash") }
                                .tint(Palette.overdue)   // 전역 .tint(Palette.accent)(RootView)가 destructive 기본 빨강을 덮는다
                        }
                        .swipeActions(edge: .leading) {
                            if !cycleAlreadyDone(item) {   // 이번 회차를 이미 닫았으면 안 그린다(dead action 방지)
                                Button { model.markDone(item) } label: { Label(item.type == "recurrence" ? "했어요" : "완료", systemImage: "checkmark") }.tint(.green)
                            }
                            // 미루기는 미리 알림을 **시점으로** 쓰는 분류에서만(지식·아이디어·추억은 뺀다 — §7(c)).
                            // **정보도 뺀다**(2026-09-14) — 「유효 기간」은 보이지만 시점이 아니라 미룰 것이 없다. 완료는 남는다.
                            if ClassSpecCatalog.schedules(item.type, .resurface) {
                                Button { model.defer7(item) } label: { Label("미루기", systemImage: "clock") }.tint(.orange)
                            }
                        }
                        .contextMenu {
                            if !cycleAlreadyDone(item) {   // 이번 회차를 이미 닫았으면 안 그린다(dead action 방지)
                                Button { model.markDone(item) } label: { Label(item.type == "recurrence" ? "했어요" : "완료", systemImage: "checkmark") }
                            }
                            if ClassSpecCatalog.schedules(item.type, .resurface) {
                                Button { model.defer7(item) } label: { Label("미루기 (시점 붙임)", systemImage: "clock") }
                            }
                            Button(role: .destructive) { model.pendingDelete = item } label: { Label("삭제", systemImage: "trash") }
                                .tint(Palette.overdue)
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
    }
}
