import SwiftUI
import SecondBrainCore

/// 보관함 — 완료(done) 처리해 받은함에서 뺀 항목들. v1은 done 필터 뷰(되돌리기 지원).
struct ArchiveView: View {
    @ObservedObject var model: InboxModel

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                if model.doneItems.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "archivebox").font(.system(size: 40)).foregroundStyle(Palette.textTertiary)
                        Text("보관함이 비었어요").font(.callout).foregroundStyle(Palette.textSecondary)
                    }
                } else {
                    List(model.doneItems, id: \.id) { item in
                        HStack(spacing: 10) {
                            TypeGlyph(type: item.type)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.raw ?? "").font(.callout).foregroundStyle(Palette.textSecondary).lineLimit(2)
                                Text(itemCaption(item)).font(.caption2).foregroundStyle(Palette.textTertiary).lineLimit(1)
                            }
                        }
                        .listRowBackground(Palette.bg)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading) {
                            Button { model.restore(item) } label: { Label("되돌리기", systemImage: "arrow.uturn.backward") }
                                .tint(Palette.accent)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { model.delete(item) } label: { Label("삭제", systemImage: "trash") }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Palette.bg)
                }
            }
            .navigationTitle("보관함")
        }
    }
}
