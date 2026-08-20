import SwiftUI
import SecondBrainCore

/// "살아있는 기억" — 앱의 심장(memory-philosophy.md §2-2).
/// 확정을 거쳐 살아남은, 시점 없는 것들(아이디어·지식·직관). 필터는 여기에 있다.
/// (윗단 = "가장 살아있는 것" 정의는 나중에 기획. v1은 필터 + 리스트만.)
struct LivingView: View {
    @ObservedObject var model: InboxModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerRow
                FilterChipsBar(filter: $model.filter, presentTypes: model.livingPresentTypes)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.bg.ignoresSafeArea())
            .hiddenNavBar()
            .navigationDestination(for: ResolvedItem.self) { DetailView(item: $0, model: model) }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("살아있는 기억").font(.largeTitle.bold()).foregroundStyle(Palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
    }

    private var content: some View {
        let items = model.livingMemories
        return List {
            if items.isEmpty {
                Text(model.filter == .all ? "아직 살아있는 기억이 없어요\n새 기억을 기억하기로 하면 여기로 와요" : "이 종류가 없어요")
                    .font(.callout).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
                    .listRowBackground(Palette.bg).listRowSeparator(.hidden)
            } else {
                ForEach(items, id: \.id) { item in
                    MemoryRow(item: item, model: model)
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
                            // 미루기는 미리 알림을 쓰는 분류에서만(정보·아이디어는 뺀다 — §7(a)). 완료는 남는다.
                            if ClassSpecCatalog.uses(item.type, .resurface) {
                                Button { model.defer7(item) } label: { Label("미루기", systemImage: "clock") }.tint(.orange)
                            }
                        }
                        .contextMenu {
                            if !cycleAlreadyDone(item) {   // 이번 회차를 이미 닫았으면 안 그린다(dead action 방지)
                                Button { model.markDone(item) } label: { Label(item.type == "recurrence" ? "했어요" : "완료", systemImage: "checkmark") }
                            }
                            if ClassSpecCatalog.uses(item.type, .resurface) {
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
