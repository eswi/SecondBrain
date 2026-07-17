import SwiftUI
import SecondBrainCore

/// 보관함 — 받은함에서 치운 것을 한 곳에서. 두 섹션: 완료 / 삭제·버림. 각각 되돌리기.
struct ArchiveView: View {
    @ObservedObject var model: InboxModel

    private var isEmpty: Bool { model.doneItems.isEmpty && model.trashed.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                if isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "archivebox").font(.system(size: 40)).foregroundStyle(Palette.textTertiary)
                        Text("보관함이 비었어요").font(.callout).foregroundStyle(Palette.textSecondary)
                    }
                } else {
                    List {
                        if !model.doneItems.isEmpty {
                            Section {
                                ForEach(model.doneItems, id: \.id) { item in
                                    row(item)
                                        .swipeActions(edge: .leading) {
                                            Button { model.restore(item) } label: { Label("되돌리기", systemImage: "arrow.uturn.backward") }
                                                .tint(Palette.accent)
                                        }
                                }
                            } header: { header("완료", model.doneItems.count) }
                        }
                        if !model.trashed.isEmpty {
                            Section {
                                ForEach(model.trashed, id: \.id) { item in
                                    row(item)
                                        .swipeActions(edge: .leading) {
                                            Button { model.restoreFromTrash(item) } label: { Label("되돌리기", systemImage: "arrow.uturn.backward") }
                                                .tint(Palette.accent)
                                        }
                                }
                            } header: { header("삭제·버림", model.trashed.count) }
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

    private func row(_ item: ResolvedItem) -> some View {
        HStack(spacing: 10) {
            TypeGlyph(type: item.type)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.raw ?? "").font(.callout).foregroundStyle(Palette.textSecondary).lineLimit(2)
                Text(itemCaption(item)).font(.caption2).foregroundStyle(Palette.textTertiary).lineLimit(1)
            }
        }
        .listRowBackground(Palette.bg)
        .listRowSeparator(.hidden)
    }

    private func header(_ title: String, _ count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textSecondary)
            Text("\(count)").font(.caption2).foregroundStyle(Palette.textTertiary)
            Spacer()
        }
        .textCase(nil)
    }
}
