import SwiftUI
import SecondBrainCore

/// "보관된 기억" — 흐름에서 빠진 것(memory-philosophy.md §2-3).
/// 완료 = 해냈다(기억할 가치) / 삭제 = 버린다. 같은 "빠짐"이지만 의미가 반대.
/// 뷰 옵션: 완료된 기억(기본) / 삭제된 기억 / 모든 기억.
/// (완전 삭제는 edit-policy.md §8 보류 — 엔진 hard-delete + 재확인 확정 후.)
struct ArchiveView: View {
    @ObservedObject var model: InboxModel

    enum ViewOption: String, CaseIterable, Identifiable {
        case done = "완료된 기억"
        case trashed = "삭제된 기억"
        case all = "모든 기억"
        var id: String { rawValue }
    }
    @State private var option: ViewOption = .done

    private var items: [ResolvedItem] {
        switch option {
        case .done:    return model.doneItems
        case .trashed: return model.trashed
        case .all:     return model.doneItems + model.trashed
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("보기", selection: $option) {
                    ForEach(ViewOption.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)

                if items.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "archivebox").font(.system(size: 40)).foregroundStyle(Palette.textTertiary)
                        Text("비었어요").font(.callout).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(items, id: \.id) { item in
                            row(item)
                                .swipeActions(edge: .leading) {
                                    Button { restore(item) } label: { Label("되돌리기", systemImage: "arrow.uturn.backward") }
                                        .tint(Palette.accent)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Palette.bg)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("보관된 기억")
        }
    }

    /// 완료/삭제 각각의 되돌리기 경로로 라우팅(항목이 done인지 삭제인지로 판별).
    private func restore(_ item: ResolvedItem) {
        if item.deleted || item.type == "discard" { model.restoreFromTrash(item) }
        else { model.restore(item) }
    }

    private func row(_ item: ResolvedItem) -> some View {
        HStack(spacing: 10) {
            TypeGlyph(type: item.type)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.raw ?? "").font(.callout).foregroundStyle(Palette.textSecondary).lineLimit(2)
                Text(itemCaption(item)).font(.caption2).foregroundStyle(Palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(item.deleted || item.type == "discard" ? "삭제" : "완료")
                .font(.caption2).foregroundStyle(Palette.textTertiary)
        }
        .listRowBackground(Palette.bg)
        .listRowSeparator(.hidden)
    }
}
